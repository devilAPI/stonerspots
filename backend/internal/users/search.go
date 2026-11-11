package users

import (
	"context"
	"database/sql"
	"net/http"
	"sort"
	"strings"
	"unicode/utf8"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/spots"
	"stonerspots/backend/internal/textmatch"
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

// searchUsers returns at most searchLimit users who are not banned and whose
// display name matches q (see textmatch): better tiers first, then the
// better match, then more spots. Always non-nil. It reads all names; there
// are few.
func (h *handler) searchUsers(ctx context.Context, q string) ([]Match, error) {
	query := textmatch.NewQuery(q)
	if query.Empty() {
		return []Match{}, nil
	}
	rows, err := h.db.QueryContext(ctx, `SELECT u.id, u.display_name, u.avatar_key, COALESCE(sc.n, 0)
		FROM users u
		LEFT JOIN (SELECT user_id, COUNT(*) AS n FROM spots WHERE status = 'active'
		  GROUP BY user_id) sc ON sc.user_id = u.id
		WHERE u.banned_at IS NULL`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	type ranked struct {
		Match
		tier  int
		score float64
	}
	var found []ranked
	for rows.Next() {
		var m ranked
		var avatarKey sql.NullString
		if err := rows.Scan(&m.ID, &m.DisplayName, &avatarKey, &m.SpotCount); err != nil {
			return nil, err
		}
		tier, score, ok := query.Match(m.DisplayName, "")
		if !ok {
			continue
		}
		m.tier, m.score = tier, score
		m.AvatarURL = app.AvatarURL(h.base, avatarKey)
		found = append(found, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.Slice(found, func(i, j int) bool {
		a, b := found[i], found[j]
		if a.tier != b.tier {
			return a.tier < b.tier
		}
		if a.score != b.score {
			return a.score > b.score
		}
		if a.SpotCount != b.SpotCount {
			return a.SpotCount > b.SpotCount
		}
		return a.ID < b.ID
	})
	list := make([]Match, 0, min(len(found), searchLimit))
	for i := 0; i < len(found) && i < searchLimit; i++ {
		list = append(list, found[i].Match)
	}
	return list, nil
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
