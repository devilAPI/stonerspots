// Package users implements public profiles and following. A profile shows a
// user's display name, join date, counts and their spots and updates. Banned
// and deleted users answer 404 everywhere here, like users that never existed.
package users

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/activity"
	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/spots"
)

const (
	defaultLimit = 20
	maxLimit     = 50
)

var errNotFound = errors.New("users: not found")

// Profile is the public view of a user.
type Profile struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
	// Bio is what the user wrote about themselves; "" when nothing.
	Bio            string    `json:"bio"`
	AvatarURL      *string   `json:"avatar_url"`
	CreatedAt      time.Time `json:"created_at"`
	SpotCount      int       `json:"spot_count"`
	UpdateCount    int       `json:"update_count"`
	FollowerCount  int       `json:"follower_count"`
	FollowingCount int       `json:"following_count"`
	// Following: the caller follows this user (false when not logged in).
	Following bool `json:"following"`
	IsMe      bool `json:"is_me"`
}

// Mount registers profile and follow routes with full paths on the /api/v1
// router.
// Following is limited per day by quota (nil: unlimited).
func Mount(r chi.Router, d app.Deps, quota *quotas.Tracker) {
	h := &handler{
		db:    d.DB,
		base:  d.Cfg.PublicBaseURL,
		spots: &spots.Repo{DB: d.DB, PublicBaseURL: d.Cfg.PublicBaseURL},
		quota: quota,
	}
	r.With(ratelimit.ByIP(ratelimit.New(d.Cfg.Limits.Search))).Get("/users/search", h.search)
	optional := r.With(auth.Optional(d.Cfg.JWTSecret))
	optional.Get("/users/{id}", h.get)
	r.Get("/users/{id}/spots", h.userSpots)
	r.Get("/users/{id}/updates", h.userUpdates)
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Put("/me/bio", h.putBio)
	authed.Put("/users/{id}/follow", h.follow)
	authed.Delete("/users/{id}/follow", h.unfollow)
}

type handler struct {
	db    *sql.DB
	base  string
	spots *spots.Repo
	quota *quotas.Tracker
}

func notFound(w http.ResponseWriter) {
	httpx.Error(w, http.StatusNotFound, "not_found", "user not found")
}

func internal(w http.ResponseWriter) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
}

func userID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id == 0 {
		notFound(w)
		return 0, false
	}
	return id, true
}

// visible reports errNotFound unless the user exists and is not banned.
func (h *handler) visible(ctx context.Context, id uint64) error {
	var one int
	err := h.db.QueryRowContext(ctx, `SELECT 1 FROM users WHERE id = ? AND banned_at IS NULL`, id).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	return err
}

// profile loads the public profile of id as seen by viewer (0: anonymous).
// Counts include only what others can see: active spots, active updates on
// active spots, and follows between users who are not banned.
func (h *handler) profile(ctx context.Context, id, viewer uint64) (Profile, error) {
	var p Profile
	var avatarKey sql.NullString
	err := h.db.QueryRowContext(ctx, `SELECT u.id, u.display_name, u.bio, u.avatar_key, u.created_at,
		(SELECT COUNT(*) FROM spots s WHERE s.user_id = u.id AND s.status = 'active'),
		(SELECT COUNT(*) FROM spot_updates su JOIN spots s ON s.id = su.spot_id
		  WHERE su.user_id = u.id AND su.status = 'active' AND s.status = 'active'),
		(SELECT COUNT(*) FROM follows f JOIN users o ON o.id = f.follower_id
		  WHERE f.followee_id = u.id AND o.banned_at IS NULL),
		(SELECT COUNT(*) FROM follows f JOIN users o ON o.id = f.followee_id
		  WHERE f.follower_id = u.id AND o.banned_at IS NULL),
		EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followee_id = u.id)
		FROM users u WHERE u.id = ? AND u.banned_at IS NULL`, viewer, id).
		Scan(&p.ID, &p.DisplayName, &p.Bio, &avatarKey, &p.CreatedAt, &p.SpotCount, &p.UpdateCount,
			&p.FollowerCount, &p.FollowingCount, &p.Following)
	if errors.Is(err, sql.ErrNoRows) {
		return p, errNotFound
	}
	p.IsMe = viewer != 0 && viewer == id
	p.AvatarURL = app.AvatarURL(h.base, avatarKey)
	return p, err
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	id, ok := userID(w, r)
	if !ok {
		return
	}
	viewer, _ := auth.UserID(r.Context())
	p, err := h.profile(r.Context(), id, viewer)
	if errors.Is(err, errNotFound) {
		notFound(w)
		return
	}
	if err != nil {
		internal(w)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

// page reads limit and the raw cursor of a paged list.
func page(w http.ResponseWriter, r *http.Request) (int, string, bool) {
	q := r.URL.Query()
	limit := defaultLimit
	if s := q.Get("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 {
			httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be a positive integer")
			return 0, "", false
		}
		limit = min(n, maxLimit)
	}
	return limit, q.Get("cursor"), true
}

func invalidCursor(w http.ResponseWriter) {
	httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "malformed cursor")
}

func encodeCursor(id uint64) string {
	return base64.RawURLEncoding.EncodeToString([]byte(strconv.FormatUint(id, 10)))
}

func decodeCursor(s string) (uint64, bool) {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return 0, false
	}
	id, err := strconv.ParseUint(string(b), 10, 64)
	return id, err == nil && id > 0
}

// userSpots lists the user's active spots, newest first, in the shape of
// GET /lists/{id}/spots.
func (h *handler) userSpots(w http.ResponseWriter, r *http.Request) {
	id, ok := userID(w, r)
	if !ok {
		return
	}
	limit, raw, ok := page(w, r)
	if !ok {
		return
	}
	var cursor uint64
	if raw != "" {
		if cursor, ok = decodeCursor(raw); !ok {
			invalidCursor(w)
			return
		}
	}
	if err := h.visible(r.Context(), id); errors.Is(err, errNotFound) {
		notFound(w)
		return
	} else if err != nil {
		internal(w)
		return
	}
	items, next, err := h.spotsOf(r.Context(), id, cursor, limit)
	if err != nil {
		internal(w)
		return
	}
	var nc *string
	if next != 0 {
		c := encodeCursor(next)
		nc = &c
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nc})
}

// spotsOf returns a page of the user's active spots, newest first, and the
// cursor of the next page (0 at the end).
func (h *handler) spotsOf(ctx context.Context, userID, cursor uint64, limit int) ([]spots.Spot, uint64, error) {
	q := `SELECT id FROM spots WHERE user_id = ? AND status = 'active'`
	args := []any{userID}
	if cursor != 0 {
		q += ` AND id < ?`
		args = append(args, cursor)
	}
	rows, err := h.db.QueryContext(ctx, q+` ORDER BY id DESC LIMIT ?`, append(args, limit+1)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var ids []uint64
	for rows.Next() {
		var id uint64
		if err := rows.Scan(&id); err != nil {
			return nil, 0, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	rows.Close()
	var next uint64
	if len(ids) > limit {
		ids, next = ids[:limit], ids[limit-1]
	}
	list, err := h.spots.ByIDs(ctx, ids)
	return list, next, err
}

// userUpdates lists the user's active updates, newest first, in the shape of
// GET /feed.
func (h *handler) userUpdates(w http.ResponseWriter, r *http.Request) {
	id, ok := userID(w, r)
	if !ok {
		return
	}
	limit, cursor, ok := page(w, r)
	if !ok {
		return
	}
	if err := h.visible(r.Context(), id); errors.Is(err, errNotFound) {
		notFound(w)
		return
	} else if err != nil {
		internal(w)
		return
	}
	items, next, err := feed.ListByAuthor(r.Context(), h.db, h.base, id, cursor, limit)
	if errors.Is(err, feed.ErrInvalidCursor) {
		invalidCursor(w)
		return
	}
	if err != nil {
		internal(w)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": next})
}

// followTarget reads the target of a follow route: the caller and the target
// id, after answering 404 for unknown or banned users and 400 for oneself.
func (h *handler) followTarget(w http.ResponseWriter, r *http.Request) (uint64, uint64, bool) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return 0, 0, false
	}
	id, ok := userID(w, r)
	if !ok {
		return 0, 0, false
	}
	if err := h.visible(r.Context(), id); errors.Is(err, errNotFound) {
		notFound(w)
		return 0, 0, false
	} else if err != nil {
		internal(w)
		return 0, 0, false
	}
	if id == uid {
		httpx.Error(w, http.StatusBadRequest, "cannot_follow_self", "you cannot follow yourself")
		return 0, 0, false
	}
	return uid, id, true
}

// follow is idempotent: following someone twice is no error. A new follow
// tells the followed user through their activity, in the same transaction.
func (h *handler) follow(w http.ResponseWriter, r *http.Request) {
	uid, id, ok := h.followTarget(w, r)
	if !ok {
		return
	}
	// each follow notifies someone: limited per day (unfollowing is free)
	if h.quota != nil && !h.quota.Allow(uid, quotas.Follows) {
		httpx.Error(w, http.StatusTooManyRequests, "quota_exceeded", "daily follow limit reached")
		return
	}
	if err := h.setFollow(r.Context(), uid, id, true); err != nil {
		internal(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// unfollow is idempotent: unfollowing someone you do not follow is no error.
// The unread follow notice goes with it, so toggling does not spam.
func (h *handler) unfollow(w http.ResponseWriter, r *http.Request) {
	uid, id, ok := h.followTarget(w, r)
	if !ok {
		return
	}
	if err := h.setFollow(r.Context(), uid, id, false); err != nil {
		internal(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// setFollow adds or removes the follow of uid on id together with its
// activity row.
func (h *handler) setFollow(ctx context.Context, uid, id uint64, on bool) error {
	tx, err := h.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	ev := activity.Event{Recipient: id, Actor: uid, Kind: activity.Follow}
	if on {
		// INSERT ... SELECT so a user deleted in between inserts nothing
		// instead of failing the foreign key.
		res, err := tx.ExecContext(ctx,
			`INSERT IGNORE INTO follows (follower_id, followee_id)
			 SELECT ?, id FROM users WHERE id = ? AND banned_at IS NULL`, uid, id)
		if err != nil {
			return err
		}
		if n, err := res.RowsAffected(); err != nil {
			return err
		} else if n > 0 {
			if err := activity.Add(ctx, tx, ev); err != nil {
				return err
			}
		}
	} else {
		if _, err := tx.ExecContext(ctx,
			`DELETE FROM follows WHERE follower_id = ? AND followee_id = ?`, uid, id); err != nil {
			return err
		}
		if err := activity.RemoveUnread(ctx, tx, ev); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// putBio answers PUT /me/bio {"bio": "..."}: sets the caller's bio ("" removes
// it) and answers with it as stored (see auth.ValidBio).
func (h *handler) putBio(w http.ResponseWriter, r *http.Request) {
	uid, _ := auth.UserID(r.Context())
	var in struct {
		Bio *string `json:"bio"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&in); err != nil || in.Bio == nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_body", `send {"bio": "..."}`)
		return
	}
	bio, ok := auth.ValidBio(*in.Bio)
	if !ok {
		httpx.Error(w, http.StatusBadRequest, "invalid_bio",
			fmt.Sprintf("bio must be at most %d characters and %d lines", auth.MaxBioLen, auth.MaxBioLines))
		return
	}
	res, err := h.db.ExecContext(r.Context(), `UPDATE users SET bio = ? WHERE id = ? AND banned_at IS NULL`, bio, uid)
	if err != nil {
		internal(w)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		// banned or gone; an unchanged bio also affects no row
		if err := h.visible(r.Context(), uid); errors.Is(err, errNotFound) {
			notFound(w)
			return
		} else if err != nil {
			internal(w)
			return
		}
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"bio": bio})
}
