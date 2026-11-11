package users

import (
	"context"
	"database/sql"
	"net/http"
	"strings"
	"unicode/utf8"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/spots"
)

// searchLimit is the most users one search returns.
const searchLimit = 20

// Match is a user found by name.
type Match struct {
	ID          uint64  `json:"id"`
	DisplayName string  `json:"display_name"`
	AvatarURL   *string `json:"avatar_url"`
	SpotCount   int     `json:"spot_count"`
}

// Search returns at most searchLimit users who are not banned and whose
// display name contains q: exact name first, then names starting with q,
// then a word starting with q, then the rest; within each, more spots
// first. The column collation makes it case- and accent-insensitive.
// Always non-nil.
func (h *handler) searchUsers(ctx context.Context, q string) ([]Match, error) {
	esc := spots.LikeEscape(q)
	rows, err := h.db.QueryContext(ctx, `SELECT u.id, u.display_name, u.avatar_key,
		(SELECT COUNT(*) FROM spots s WHERE s.user_id = u.id AND s.status = 'active') AS n
		FROM users u
		WHERE u.banned_at IS NULL AND u.display_name LIKE ?
		ORDER BY CASE WHEN u.display_name = ? THEN 0 WHEN u.display_name LIKE ? THEN 1
		  WHEN u.display_name LIKE ? THEN 2 ELSE 3 END, n DESC, u.id ASC
		LIMIT ?`, "%"+esc+"%", q, esc+"%", "% "+esc+"%", searchLimit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	list := []Match{}
	for rows.Next() {
		var m Match
		var avatarKey sql.NullString
		if err := rows.Scan(&m.ID, &m.DisplayName, &avatarKey, &m.SpotCount); err != nil {
			return nil, err
		}
		m.AvatarURL = app.AvatarURL(h.base, avatarKey)
		list = append(list, m)
	}
	return list, rows.Err()
}

// search answers GET /users/search?q=.
func (h *handler) search(w http.ResponseWriter, r *http.Request) {
	q := strings.Join(strings.Fields(r.URL.Query().Get("q")), " ")
	if n := utf8.RuneCountInString(q); n < spots.SearchMinLen || n > spots.SearchMaxLen {
		httpx.Error(w, http.StatusBadRequest, "invalid_query", "q must be 2-80 characters")
		return
	}
	list, err := h.searchUsers(r.Context(), q)
	if err != nil {
		internal(w)
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}
