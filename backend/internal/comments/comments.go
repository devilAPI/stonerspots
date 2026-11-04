// Package comments implements comments under spot updates: a thread per
// update, oldest first, written by logged-in users and removable by their
// author or an admin.
package comments

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/activity"
	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/quotas"
)

const (
	// MaxBodyLen is the longest comment in characters (runes).
	MaxBodyLen   = 500
	defaultLimit = 20
	maxLimit     = 50
)

var (
	// ErrNotFound: the comment does not exist, or the caller may not delete it.
	ErrNotFound = errors.New("comments: not found")
	// errUpdateNotFound: the update does not exist or is not visible.
	errUpdateNotFound = errors.New("comments: update not found")
)

// Mount registers comment routes with full paths on the /api/v1 router.
func Mount(r chi.Router, d app.Deps, quota *quotas.Tracker) {
	h := &handler{db: d.DB, quota: quota, base: d.Cfg.PublicBaseURL, guard: auth.GuardFor(d)}
	r.With(auth.Optional(d.Cfg.JWTSecret)).Get("/updates/{id}/comments", h.list)
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Post("/updates/{id}/comments", h.create)
	authed.Delete("/comments/{id}", h.delete)
}

type handler struct {
	db    *sql.DB
	quota *quotas.Tracker
	base  string // public base URL, for avatar URLs
	guard *auth.Guard
}

type author struct {
	ID          uint64  `json:"id"`
	DisplayName string  `json:"display_name"`
	AvatarURL   *string `json:"avatar_url"`
}

// Comment is one comment as the API returns it.
type Comment struct {
	ID        uint64    `json:"id"`
	UpdateID  uint64    `json:"update_id"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
	Author    author    `json:"author"`
	// Mine is true when the caller wrote the comment.
	Mine bool `json:"mine"`
}

const selectComment = `SELECT c.id, c.update_id, c.body, c.created_at, a.id, a.display_name, a.avatar_key
  FROM comments c JOIN users a ON a.id = c.user_id`

func scan(row interface{ Scan(...any) error }, caller uint64, base string) (Comment, error) {
	var c Comment
	var avatarKey sql.NullString
	err := row.Scan(&c.ID, &c.UpdateID, &c.Body, &c.CreatedAt, &c.Author.ID, &c.Author.DisplayName, &avatarKey)
	c.Author.AvatarURL = app.AvatarURL(base, avatarKey)
	c.CreatedAt = c.CreatedAt.UTC()
	c.Mine = caller != 0 && c.Author.ID == caller
	return c, err
}

// visibleUpdate is the condition for an update whose comments can be read
// and written: the update and its spot are active.
const visibleUpdate = `SELECT u.id FROM spot_updates u JOIN spots s ON s.id = u.spot_id
  WHERE u.id = ? AND u.status = 'active' AND s.status = 'active'`

func encodeCursor(id uint64) string {
	b, _ := json.Marshal(struct {
		ID uint64 `json:"id"`
	}{id})
	return base64.RawURLEncoding.EncodeToString(b)
}

func decodeCursor(s string) (uint64, bool) {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return 0, false
	}
	var p struct {
		ID *uint64 `json:"id"`
	}
	if json.Unmarshal(b, &p) != nil || p.ID == nil || *p.ID == 0 {
		return 0, false
	}
	return *p.ID, true
}

func internal(w http.ResponseWriter) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
}

func updateNotFound(w http.ResponseWriter) {
	httpx.Error(w, http.StatusNotFound, "not_found", "update not found")
}

func pathID(r *http.Request) (uint64, bool) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	return id, err == nil && id != 0
}

// list answers GET /updates/{id}/comments: active comments, oldest first.
func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id, ok := pathID(r)
	if !ok {
		updateNotFound(w)
		return
	}
	limit := defaultLimit
	if s := r.URL.Query().Get("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 {
			httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be a positive integer")
			return
		}
		limit = min(n, maxLimit)
	}
	var after uint64
	if s := r.URL.Query().Get("cursor"); s != "" {
		c, good := decodeCursor(s)
		if !good {
			httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "malformed cursor")
			return
		}
		after = c
	}
	var one uint64
	err := h.db.QueryRowContext(ctx, visibleUpdate, id).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		updateNotFound(w)
		return
	}
	if err != nil {
		internal(w)
		return
	}
	caller, _ := auth.UserID(ctx)
	rows, err := h.db.QueryContext(ctx, selectComment+`
		WHERE c.update_id = ? AND c.status = 'active' AND c.id > ?
		ORDER BY c.id ASC LIMIT ?`, id, after, limit+1)
	if err != nil {
		internal(w)
		return
	}
	defer rows.Close()
	items := []Comment{}
	for rows.Next() {
		c, err := scan(rows, caller, h.base)
		if err != nil {
			internal(w)
			return
		}
		items = append(items, c)
	}
	if err := rows.Err(); err != nil {
		internal(w)
		return
	}
	var next *string
	if len(items) > limit {
		items = items[:limit]
		c := encodeCursor(items[limit-1].ID)
		next = &c
	}
	httpx.JSON(w, http.StatusOK, struct {
		Items      []Comment `json:"items"`
		NextCursor *string   `json:"next_cursor"`
	}{items, next})
}

// Create adds a comment by userID under a visible update and tells the
// update's author through their activity. The body is trimmed and must be
// 1..MaxBodyLen characters.
func Create(ctx context.Context, db *sql.DB, base string, userID, updateID uint64, body string) (Comment, error) {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return Comment{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	var owner, spotID uint64
	// lock the update so it cannot be deleted between the check and the insert
	err = tx.QueryRowContext(ctx, `SELECT u.user_id, u.spot_id FROM spot_updates u JOIN spots s ON s.id = u.spot_id
		WHERE u.id = ? AND u.status = 'active' AND s.status = 'active' FOR UPDATE`, updateID).Scan(&owner, &spotID)
	if errors.Is(err, sql.ErrNoRows) {
		return Comment{}, errUpdateNotFound
	}
	if err != nil {
		return Comment{}, err
	}
	res, err := tx.ExecContext(ctx, `INSERT INTO comments (update_id, user_id, body) VALUES (?, ?, ?)`, updateID, userID, body)
	if err != nil {
		return Comment{}, err
	}
	lid, err := res.LastInsertId()
	if err != nil {
		return Comment{}, err
	}
	if err := activity.Add(ctx, tx, activity.Event{
		Recipient: owner, Actor: userID, Kind: activity.Comment,
		SpotID: spotID, UpdateID: updateID, CommentID: uint64(lid),
	}); err != nil {
		return Comment{}, err
	}
	c, err := scan(tx.QueryRowContext(ctx, selectComment+` WHERE c.id = ?`, lid), userID, base)
	if err != nil {
		return Comment{}, err
	}
	return c, tx.Commit()
}

// create answers POST /updates/{id}/comments.
func (h *handler) create(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	id, ok := pathID(r)
	if !ok {
		updateNotFound(w)
		return
	}
	var in struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	body := strings.TrimSpace(in.Body)
	if n := utf8.RuneCountInString(body); n == 0 || n > MaxBodyLen {
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "body must be 1 to 500 characters")
		return
	}
	if h.quota != nil && !h.quota.Allow(uid, quotas.Comments) {
		httpx.Error(w, http.StatusTooManyRequests, "quota_exceeded", "daily comment limit reached")
		return
	}
	c, err := Create(r.Context(), h.db, h.base, uid, id, body)
	switch {
	case errors.Is(err, errUpdateNotFound):
		updateNotFound(w)
	case err != nil:
		internal(w)
	default:
		httpx.JSON(w, http.StatusCreated, c)
	}
}

// errNotAuthor: the comment exists but byUserID did not write it.
var errNotAuthor = errors.New("comments: not the author")

// Delete removes a comment with the reports about it (reports are
// polymorphic, no FK). With byUserID set only the author may delete it
// (errNotAuthor otherwise); byUserID 0 skips the check (admins, who have
// passed their 2FA check).
func Delete(ctx context.Context, db *sql.DB, id, byUserID uint64) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	var owner uint64
	err = tx.QueryRowContext(ctx, `SELECT user_id FROM comments WHERE id = ? FOR UPDATE`, id).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if byUserID != 0 && owner != byUserID {
		return errNotAuthor
	}
	for _, q := range []string{
		`DELETE FROM reports WHERE target_type = 'comment' AND target_id = ?`,
		`DELETE FROM comments WHERE id = ?`,
	} {
		if _, err := tx.ExecContext(ctx, q, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// delete answers DELETE /comments/{id}.
func (h *handler) delete(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	id, ok := pathID(r)
	if !ok {
		httpx.Error(w, http.StatusNotFound, "not_found", "comment not found")
		return
	}
	err := Delete(r.Context(), h.db, id, uid)
	if errors.Is(err, errNotAuthor) {
		// someone else's comment: only an admin, with 2FA, may delete it
		admin, handled := h.guard.AdminPowers(w, r)
		if handled {
			return
		}
		err = ErrNotFound
		if admin {
			err = Delete(r.Context(), h.db, id, 0)
		}
	}
	switch {
	case errors.Is(err, ErrNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "comment not found")
	case err != nil:
		internal(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}
