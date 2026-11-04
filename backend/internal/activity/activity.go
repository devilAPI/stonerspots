// Package activity records what happens to a user's own content (someone
// followed them, commented on their update, liked or rated their spot) and
// serves it as GET /me/activity.
//
// Rows are written by the packages that perform the action (users, comments,
// engagement, reviews) through Add, inside the same transaction as the action
// itself: an action and its activity row are stored together or not at all.
// Undoing an action (unfollow, unlike, deleting a review) removes the matching
// unread row with RemoveUnread, so toggling does not pile up notices.
package activity

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

// Kind is what happened.
type Kind string

const (
	Follow  Kind = "follow"
	Comment Kind = "comment"
	Like    Kind = "like"
	Review  Kind = "review"
)

const (
	defaultLimit = 20
	maxLimit     = 50
	// PreviewLen is the length in characters of a comment preview.
	PreviewLen = 120
)

// Execer is satisfied by *sql.DB and *sql.Tx.
type Execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// Event describes one activity row. Recipient is the owner of the content,
// Actor the user who acted. SpotID, UpdateID and CommentID are 0 when they
// do not apply.
type Event struct {
	Recipient uint64
	Actor     uint64
	Kind      Kind
	SpotID    uint64
	UpdateID  uint64
	CommentID uint64
}

func nullable(id uint64) any {
	if id == 0 {
		return nil
	}
	return id
}

// Add writes an activity row. Acting on your own content writes nothing.
func Add(ctx context.Context, ex Execer, e Event) error {
	if e.Recipient == 0 || e.Actor == 0 || e.Recipient == e.Actor {
		return nil
	}
	_, err := ex.ExecContext(ctx,
		`INSERT INTO activity (user_id, actor_id, kind, spot_id, update_id, comment_id) VALUES (?, ?, ?, ?, ?, ?)`,
		e.Recipient, e.Actor, string(e.Kind), nullable(e.SpotID), nullable(e.UpdateID), nullable(e.CommentID))
	return err
}

// RemoveUnread deletes the unread rows of e.Kind by e.Actor for e.Recipient
// about e.SpotID (0: rows without a spot). Rows already read stay.
func RemoveUnread(ctx context.Context, ex Execer, e Event) error {
	_, err := ex.ExecContext(ctx,
		`DELETE FROM activity WHERE user_id = ? AND actor_id = ? AND kind = ? AND spot_id <=> ? AND read_at IS NULL`,
		e.Recipient, e.Actor, string(e.Kind), nullable(e.SpotID))
	return err
}

// visibleFrom joins an activity row (alias a) with what it is about and keeps
// only rows that can still be shown: the actor is not banned, and the spot,
// update and comment (where set) are active. A review row needs the actor's
// review of the spot to still exist and be active.
const visibleFrom = `
  FROM activity a
  JOIN users act ON act.id = a.actor_id AND act.banned_at IS NULL
  LEFT JOIN spots s ON s.id = a.spot_id
  LEFT JOIN spot_updates up ON up.id = a.update_id
  LEFT JOIN comments c ON c.id = a.comment_id
  WHERE a.user_id = ?
    AND (a.spot_id IS NULL OR s.status = 'active')
    AND (a.update_id IS NULL OR up.status = 'active')
    AND (a.comment_id IS NULL OR c.status = 'active')
    AND (a.kind <> 'review' OR EXISTS (SELECT 1 FROM spot_reviews r
         WHERE r.spot_id = a.spot_id AND r.user_id = a.actor_id AND r.status = 'active'))`

// UnreadCount counts the visible unread rows of userID.
func UnreadCount(ctx context.Context, db *sql.DB, userID uint64) (int, error) {
	var n int
	err := db.QueryRowContext(ctx, `SELECT COUNT(*)`+visibleFrom+` AND a.read_at IS NULL`, userID).Scan(&n)
	return n, err
}

// Actor is the user who acted.
type Actor struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
}

// Spot is the spot an item is about.
type Spot struct {
	ID    uint64 `json:"id"`
	Title string `json:"title"`
}

// Item is one activity row as GET /me/activity returns it.
type Item struct {
	ID        uint64    `json:"id"`
	Kind      Kind      `json:"kind"`
	CreatedAt time.Time `json:"created_at"`
	Read      bool      `json:"read"`
	Actor     Actor     `json:"actor"`
	Spot      *Spot     `json:"spot"`
	UpdateID  *uint64   `json:"update_id"`
	CommentID *uint64   `json:"comment_id"`
	// CommentPreview is the first PreviewLen characters of the comment
	// (kind comment only).
	CommentPreview *string `json:"comment_preview"`
}

// List returns a page of userID's visible activity, newest first, starting
// below the id before (0: from the top), and the id to continue from (0 at
// the end).
func List(ctx context.Context, db *sql.DB, userID, before uint64, limit int) ([]Item, uint64, error) {
	q := `SELECT a.id, a.kind, a.created_at, a.read_at IS NOT NULL, act.id, act.display_name,
	  s.id, s.title, a.update_id, a.comment_id, LEFT(c.body, ` + strconv.Itoa(PreviewLen) + `)` + visibleFrom
	args := []any{userID}
	if before != 0 {
		q += ` AND a.id < ?`
		args = append(args, before)
	}
	rows, err := db.QueryContext(ctx, q+` ORDER BY a.id DESC LIMIT ?`, append(args, limit+1)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []Item{}
	for rows.Next() {
		var (
			it                  Item
			spotID              sql.NullInt64
			spotTitle, preview  sql.NullString
			updateID, commentID sql.NullInt64
		)
		if err := rows.Scan(&it.ID, &it.Kind, &it.CreatedAt, &it.Read, &it.Actor.ID, &it.Actor.DisplayName,
			&spotID, &spotTitle, &updateID, &commentID, &preview); err != nil {
			return nil, 0, err
		}
		it.CreatedAt = it.CreatedAt.UTC()
		if spotID.Valid {
			it.Spot = &Spot{ID: uint64(spotID.Int64), Title: spotTitle.String}
		}
		if updateID.Valid {
			v := uint64(updateID.Int64)
			it.UpdateID = &v
		}
		if commentID.Valid {
			v := uint64(commentID.Int64)
			it.CommentID = &v
		}
		if it.Kind == Comment && preview.Valid {
			p := preview.String
			it.CommentPreview = &p
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	var next uint64
	if len(items) > limit {
		items = items[:limit]
		next = items[limit-1].ID
	}
	return items, next, nil
}

// MarkRead marks userID's unread rows up to and including upTo as read
// (upTo 0: all of them).
func MarkRead(ctx context.Context, db *sql.DB, userID, upTo uint64) error {
	q := `UPDATE activity SET read_at = CURRENT_TIMESTAMP WHERE user_id = ? AND read_at IS NULL`
	args := []any{userID}
	if upTo != 0 {
		q += ` AND id <= ?`
		args = append(args, upTo)
	}
	_, err := db.ExecContext(ctx, q, args...)
	return err
}

// UnreadCounter returns UnreadCount bound to db, for auth.MountOptions.
func UnreadCounter(db *sql.DB) func(context.Context, uint64) (int, error) {
	return func(ctx context.Context, userID uint64) (int, error) {
		return UnreadCount(ctx, db, userID)
	}
}

// Mount registers GET /me/activity and POST /me/activity/read on the
// /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{db: d.DB}
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Get("/me/activity", h.list)
	authed.Post("/me/activity/read", h.read)
}

type handler struct{ db *sql.DB }

func internal(w http.ResponseWriter) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
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

func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	q := r.URL.Query()
	limit := defaultLimit
	if s := q.Get("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 {
			httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be a positive integer")
			return
		}
		limit = min(n, maxLimit)
	}
	var before uint64
	if s := q.Get("cursor"); s != "" {
		if before, ok = decodeCursor(s); !ok {
			httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "malformed cursor")
			return
		}
	}
	items, next, err := List(r.Context(), h.db, uid, before, limit)
	if err != nil {
		internal(w)
		return
	}
	var nc *string
	if next != 0 {
		c := encodeCursor(next)
		nc = &c
	}
	httpx.JSON(w, http.StatusOK, struct {
		Items      []Item  `json:"items"`
		NextCursor *string `json:"next_cursor"`
	}{items, nc})
}

// read answers POST /me/activity/read. The body {"up_to": id} marks rows up
// to id as read; an empty body (or no up_to) marks all of them.
func (h *handler) read(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	var in struct {
		UpTo uint64 `json:"up_to"`
	}
	err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&in)
	if err != nil && !errors.Is(err, io.EOF) {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	if err := MarkRead(r.Context(), h.db, uid, in.UpTo); err != nil {
		internal(w)
		return
	}
	n, err := UnreadCount(r.Context(), h.db, uid)
	if err != nil {
		internal(w)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]int{"unread_activity": n})
}
