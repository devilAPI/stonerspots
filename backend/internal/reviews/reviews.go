// Package reviews implements one star review (1..5, optional text) per user and spot.
package reviews

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

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

const (
	defaultLimit = 20
	maxLimit     = 50
	maxBodyLen   = 1000
)

// Mount registers review routes with full paths on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{db: d.DB}
	r.With(auth.Optional(d.Cfg.JWTSecret)).Get("/spots/{id}/reviews", h.list)
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Put("/spots/{id}/review", h.put)
	authed.Delete("/spots/{id}/review", h.delete)
}

type handler struct{ db *sql.DB }

type author struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
}

type review struct {
	ID        uint64    `json:"id"`
	Rating    int       `json:"rating"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Author    author    `json:"author"`
}

type summary struct {
	Avg          float64        `json:"avg"`
	Count        int            `json:"count"`
	Distribution map[string]int `json:"distribution"`
}

const selectReview = `SELECT r.id, r.rating, r.body, r.created_at, r.updated_at, u.id, u.display_name
  FROM spot_reviews r JOIN users u ON u.id = r.user_id`

func scanReview(row interface{ Scan(...any) error }) (review, error) {
	var v review
	err := row.Scan(&v.ID, &v.Rating, &v.Body, &v.CreatedAt, &v.UpdatedAt, &v.Author.ID, &v.Author.DisplayName)
	return v, err
}

func internal(w http.ResponseWriter) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
}

func spotID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return 0, false
	}
	return id, true
}

// spotOwner returns the author of an active spot, or sql.ErrNoRows.
func (h *handler) spotOwner(ctx context.Context, id uint64) (uint64, error) {
	var owner uint64
	err := h.db.QueryRowContext(ctx, `SELECT user_id FROM spots WHERE id = ? AND status = 'active'`, id).Scan(&owner)
	return owner, err
}

func (h *handler) put(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	sid, ok := spotID(w, r)
	if !ok {
		return
	}
	var in struct {
		Rating *json.Number `json:"rating"`
		Body   string       `json:"body"`
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
	dec.UseNumber()
	if err := dec.Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body is not valid JSON")
		return
	}
	rating := 0
	if in.Rating != nil {
		if n, err := strconv.Atoi(in.Rating.String()); err == nil {
			rating = n
		}
	}
	if rating < 1 || rating > 5 {
		httpx.Error(w, http.StatusBadRequest, "invalid_rating", "rating must be an integer from 1 to 5")
		return
	}
	body := strings.TrimSpace(in.Body)
	if utf8.RuneCountInString(body) > maxBodyLen {
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "body must be at most 1000 characters")
		return
	}
	owner, err := h.spotOwner(r.Context(), sid)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	if err != nil {
		internal(w)
		return
	}
	if owner == uid {
		httpx.Error(w, http.StatusForbidden, "own_spot", "you cannot review your own spot")
		return
	}
	if _, err := h.db.ExecContext(r.Context(),
		`INSERT INTO spot_reviews (spot_id, user_id, rating, body) VALUES (?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE rating = VALUES(rating), body = VALUES(body)`,
		sid, uid, rating, body); err != nil {
		// A spot deleted in between violates the FK.
		internal(w)
		return
	}
	v, err := scanReview(h.db.QueryRowContext(r.Context(), selectReview+` WHERE r.spot_id = ? AND r.user_id = ?`, sid, uid))
	if err != nil {
		internal(w)
		return
	}
	httpx.JSON(w, http.StatusOK, v)
}

func (h *handler) delete(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	sid, ok := spotID(w, r)
	if !ok {
		return
	}
	tx, err := h.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w)
		return
	}
	defer tx.Rollback() //nolint:errcheck
	var id uint64
	err = tx.QueryRowContext(r.Context(), `SELECT id FROM spot_reviews WHERE spot_id = ? AND user_id = ? FOR UPDATE`, sid, uid).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "review not found")
		return
	}
	if err != nil {
		internal(w)
		return
	}
	if err := deleteInTx(r.Context(), tx, id); err != nil {
		internal(w)
		return
	}
	if err := tx.Commit(); err != nil {
		internal(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
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
	sid, ok := spotID(w, r)
	if !ok {
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
	var cur uint64
	if c := q.Get("cursor"); c != "" {
		id, ok := decodeCursor(c)
		if !ok {
			httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "malformed cursor")
			return
		}
		cur = id
	}
	ctx := r.Context()
	if _, err := h.spotOwner(ctx, sid); errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	} else if err != nil {
		internal(w)
		return
	}

	sum := summary{Distribution: map[string]int{"1": 0, "2": 0, "3": 0, "4": 0, "5": 0}}
	rows, err := h.db.QueryContext(ctx,
		`SELECT rating, COUNT(*) FROM spot_reviews WHERE spot_id = ? AND status = 'active' GROUP BY rating`, sid)
	if err != nil {
		internal(w)
		return
	}
	total := 0
	for rows.Next() {
		var rating, n int
		if err := rows.Scan(&rating, &n); err != nil {
			rows.Close()
			internal(w)
			return
		}
		sum.Distribution[strconv.Itoa(rating)] = n
		sum.Count += n
		total += rating * n
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		internal(w)
		return
	}
	if sum.Count > 0 {
		// round half up to one decimal using integers
		sum.Avg = float64((total*20+sum.Count)/(2*sum.Count)) / 10
	}

	out := struct {
		Summary    summary  `json:"summary"`
		Mine       *review  `json:"mine"`
		Items      []review `json:"items"`
		NextCursor *string  `json:"next_cursor"`
	}{Summary: sum, Items: []review{}}

	if uid, ok := auth.UserID(ctx); ok {
		v, err := scanReview(h.db.QueryRowContext(ctx,
			selectReview+` WHERE r.spot_id = ? AND r.user_id = ? AND r.status = 'active'`, sid, uid))
		if err == nil {
			out.Mine = &v
		} else if !errors.Is(err, sql.ErrNoRows) {
			internal(w)
			return
		}
	}

	query := selectReview + ` WHERE r.spot_id = ? AND r.status = 'active'`
	args := []any{sid}
	if cur != 0 {
		query += ` AND r.id < ?`
		args = append(args, cur)
	}
	query += ` ORDER BY r.id DESC LIMIT ?`
	args = append(args, limit+1)
	rows, err = h.db.QueryContext(ctx, query, args...)
	if err != nil {
		internal(w)
		return
	}
	defer rows.Close()
	for rows.Next() {
		v, err := scanReview(rows)
		if err != nil {
			internal(w)
			return
		}
		out.Items = append(out.Items, v)
	}
	if rows.Err() != nil {
		internal(w)
		return
	}
	if len(out.Items) > limit {
		out.Items = out.Items[:limit]
		c := encodeCursor(out.Items[limit-1].ID)
		out.NextCursor = &c
	}
	httpx.JSON(w, http.StatusOK, out)
}
