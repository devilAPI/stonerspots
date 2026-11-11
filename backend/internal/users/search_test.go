package users_test

import (
	"net/url"
	"strings"
	"testing"

	"stonerspots/backend/internal/testutil"
)

type match struct {
	ID          uint64  `json:"id"`
	DisplayName string  `json:"display_name"`
	AvatarURL   *string `json:"avatar_url"`
	SpotCount   int     `json:"spot_count"`
}

func TestSearchUsersByName(t *testing.T) {
	db, h := setup(t)
	name := func(id uint64, n string) uint64 {
		exec(t, db, `UPDATE users SET display_name = ? WHERE id = ?`, n, id)
		return id
	}
	exact := name(testutil.NewUser(t, db), "Ganja")
	prefixFew := name(testutil.NewUser(t, db), "GanjaGuru")
	prefixMany := name(testutil.NewUser(t, db), "Ganjamann")
	word := name(testutil.NewUser(t, db), "Der ganja Typ")
	inside := name(testutil.NewUser(t, db), "MegaGanja")
	banned := name(testutil.NewUser(t, db), "Ganja Banned")
	name(testutil.NewUser(t, db), "Someone else")
	exec(t, db, `UPDATE users SET banned_at = NOW() WHERE id = ?`, banned)
	newSpot(t, db, prefixMany, "a")
	newSpot(t, db, prefixMany, "b")
	hidden := newSpot(t, db, prefixFew, "hidden")
	exec(t, db, `UPDATE spots SET status = 'hidden' WHERE id = ?`, hidden)

	w := do(t, h, "GET", "/users/search?q="+url.QueryEscape("  gAnJa "), 0)
	if w.Code != 200 {
		t.Fatalf("search: %d %s", w.Code, w.Body)
	}
	got := decode[[]match](t, w)
	want := []uint64{exact, prefixMany, prefixFew, word, inside}
	if len(got) != len(want) {
		t.Fatalf("got %+v", got)
	}
	for i, id := range want {
		if got[i].ID != id {
			t.Fatalf("#%d: %+v, want id %d (all: %+v)", i, got[i], id, got)
		}
	}
	if got[1].SpotCount != 2 || got[2].SpotCount != 0 {
		t.Fatalf("spot counts must cover only active spots: %+v", got)
	}

	if w := do(t, h, "GET", "/users/search?q="+url.QueryEscape("%_"), 0); w.Code != 200 || strings.TrimSpace(w.Body.String()) != "[]" {
		t.Fatalf("wildcards must match literally: %d %s", w.Code, w.Body)
	}
	for _, q := range []string{"", "g", " g ", strings.Repeat("a", 81)} {
		if w := do(t, h, "GET", "/users/search?q="+url.QueryEscape(q), 0); w.Code != 400 {
			t.Fatalf("q=%q: %d", q, w.Code)
		}
	}
	// the route does not shadow profiles
	if p := getProfile(t, h, exact, 0); p.DisplayName != "Ganja" {
		t.Fatalf("profile: %+v", p)
	}
}
