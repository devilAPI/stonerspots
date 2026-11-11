package users_test

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
	"stonerspots/backend/internal/users"
)

type profile struct {
	ID             uint64    `json:"id"`
	DisplayName    string    `json:"display_name"`
	CreatedAt      time.Time `json:"created_at"`
	SpotCount      int       `json:"spot_count"`
	UpdateCount    int       `json:"update_count"`
	FollowerCount  int       `json:"follower_count"`
	FollowingCount int       `json:"following_count"`
	Following      bool      `json:"following"`
	IsMe           bool      `json:"is_me"`
}

type spotPage struct {
	Items []struct {
		ID       uint64   `json:"id"`
		Title    string   `json:"title"`
		CoverURL string   `json:"cover_url"`
		Tags     []string `json:"tags"`
	} `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

type updatePage struct {
	Items []struct {
		ID     uint64 `json:"id"`
		Body   string `json:"body"`
		Author struct {
			ID          uint64 `json:"id"`
			DisplayName string `json:"display_name"`
		} `json:"author"`
		Spot struct {
			ID uint64 `json:"id"`
		} `json:"spot"`
		Photos []struct {
			URL string `json:"url"`
		} `json:"photos"`
	} `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	users.Mount(r, app.Deps{DB: db, Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://test",
	}}, nil)
	return db, r
}

func exec(t *testing.T, db *sql.DB, q string, args ...any) int64 {
	t.Helper()
	res, err := db.Exec(q, args...)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return id
}

func newSpot(t *testing.T, db *sql.DB, owner uint64, title string) uint64 {
	t.Helper()
	return uint64(exec(t, db, `INSERT INTO spots (user_id, title, description, location)
		VALUES (?, ?, 'd', ST_GeomFromText('POINT(10 50)'))`, owner, title))
}

func newUpdate(t *testing.T, db *sql.DB, spot, owner uint64, body string) uint64 {
	t.Helper()
	return uint64(exec(t, db, `INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, ?)`, spot, owner, body))
}

func do(t *testing.T, h http.Handler, method, path string, user uint64) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, nil)
	if user != 0 {
		req.Header.Set("Authorization", "Bearer "+testutil.Token(t, user))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

func decode[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
	return v
}

func getProfile(t *testing.T, h http.Handler, id, viewer uint64) profile {
	t.Helper()
	w := do(t, h, "GET", fmt.Sprintf("/users/%d", id), viewer)
	if w.Code != 200 {
		t.Fatalf("profile %d: %d %s", id, w.Code, w.Body)
	}
	return decode[profile](t, w)
}

func TestProfileCountsOnlyVisibleContent(t *testing.T) {
	db, h := setup(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s1 := newSpot(t, db, u, "one")
	newSpot(t, db, u, "two")
	hiddenSpot := newSpot(t, db, u, "hidden")
	exec(t, db, `UPDATE spots SET status = 'hidden' WHERE id = ?`, hiddenSpot)
	newUpdate(t, db, s1, u, "a")
	newUpdate(t, db, s1, u, "b")
	hiddenUpd := newUpdate(t, db, s1, u, "c")
	exec(t, db, `UPDATE spot_updates SET status = 'hidden' WHERE id = ?`, hiddenUpd)
	newUpdate(t, db, hiddenSpot, u, "on a hidden spot")
	newUpdate(t, db, s1, other, "someone else")

	p := getProfile(t, h, u, 0)
	if p.ID != u || p.DisplayName == "" || p.CreatedAt.IsZero() {
		t.Fatalf("profile: %+v", p)
	}
	if p.SpotCount != 2 || p.UpdateCount != 2 || p.FollowerCount != 0 || p.FollowingCount != 0 {
		t.Fatalf("counts: %+v", p)
	}
	if p.Following || p.IsMe {
		t.Fatalf("anonymous flags: %+v", p)
	}
	if me := getProfile(t, h, u, u); !me.IsMe || me.Following {
		t.Fatalf("own profile: %+v", me)
	}
	if o := getProfile(t, h, u, other); o.IsMe {
		t.Fatalf("other viewer: %+v", o)
	}
}

func TestFollowAndUnfollow(t *testing.T) {
	db, h := setup(t)
	me, alice := testutil.NewUser(t, db), testutil.NewUser(t, db)
	path := fmt.Sprintf("/users/%d/follow", alice)

	if w := do(t, h, "PUT", path, 0); w.Code != 401 {
		t.Fatalf("anonymous follow: %d", w.Code)
	}
	for i := 0; i < 2; i++ { // idempotent
		if w := do(t, h, "PUT", path, me); w.Code != 204 {
			t.Fatalf("follow #%d: %d %s", i, w.Code, w.Body)
		}
	}
	if p := getProfile(t, h, alice, me); !p.Following || p.FollowerCount != 1 || p.FollowingCount != 0 {
		t.Fatalf("after follow: %+v", p)
	}
	if p := getProfile(t, h, me, me); p.FollowingCount != 1 || p.FollowerCount != 0 {
		t.Fatalf("my counts: %+v", p)
	}
	if p := getProfile(t, h, alice, 0); p.Following || p.FollowerCount != 1 {
		t.Fatalf("anonymous view: %+v", p)
	}

	for i := 0; i < 2; i++ {
		if w := do(t, h, "DELETE", path, me); w.Code != 204 {
			t.Fatalf("unfollow #%d: %d %s", i, w.Code, w.Body)
		}
	}
	if p := getProfile(t, h, alice, me); p.Following || p.FollowerCount != 0 {
		t.Fatalf("after unfollow: %+v", p)
	}
}

func TestCannotFollowYourself(t *testing.T) {
	db, h := setup(t)
	me := testutil.NewUser(t, db)
	w := do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", me), me)
	if w.Code != 400 {
		t.Fatalf("status %d %s", w.Code, w.Body)
	}
	if e := decode[struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}](t, w); e.Error.Code != "cannot_follow_self" {
		t.Fatalf("body %s", w.Body)
	}
}

func TestBannedAndDeletedUsersAre404(t *testing.T) {
	db, h := setup(t)
	me, banned, gone := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	exec(t, db, `INSERT INTO follows (follower_id, followee_id) VALUES (?, ?), (?, ?)`, banned, me, me, banned)
	exec(t, db, `UPDATE users SET banned_at = NOW() WHERE id = ?`, banned)
	exec(t, db, `DELETE FROM users WHERE id = ?`, gone)

	for _, id := range []uint64{banned, gone, 999999} {
		for _, p := range []string{"", "/spots", "/updates"} {
			if w := do(t, h, "GET", fmt.Sprintf("/users/%d%s", id, p), me); w.Code != 404 {
				t.Fatalf("GET user %d%s: %d", id, p, w.Code)
			}
		}
		if w := do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", id), me); w.Code != 404 {
			t.Fatalf("follow %d: %d", id, w.Code)
		}
	}
	if w := do(t, h, "GET", "/users/abc", me); w.Code != 404 {
		t.Fatalf("bad id: %d", w.Code)
	}
	// A banned user does not count as follower or followee.
	if p := getProfile(t, h, me, me); p.FollowerCount != 0 || p.FollowingCount != 0 {
		t.Fatalf("counts with banned user: %+v", p)
	}
}

func TestDeletingUserRemovesFollows(t *testing.T) {
	db, h := setup(t)
	me, alice := testutil.NewUser(t, db), testutil.NewUser(t, db)
	if w := do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", alice), me); w.Code != 204 {
		t.Fatalf("follow: %d", w.Code)
	}
	exec(t, db, `DELETE FROM users WHERE id = ?`, alice)
	var n int
	db.QueryRow(`SELECT COUNT(*) FROM follows`).Scan(&n)
	if n != 0 {
		t.Fatalf("%d follows left", n)
	}
}

func TestUserSpotsPaging(t *testing.T) {
	db, h := setup(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	var ids []uint64
	for i := 0; i < 5; i++ {
		ids = append(ids, newSpot(t, db, u, fmt.Sprintf("s%d", i)))
	}
	exec(t, db, `UPDATE spots SET status = 'hidden' WHERE id = ?`, ids[2])
	newSpot(t, db, other, "not mine")

	var got []uint64
	cursor := ""
	for page := 0; ; page++ {
		path := fmt.Sprintf("/users/%d/spots?limit=2", u)
		if cursor != "" {
			path += "&cursor=" + cursor
		}
		w := do(t, h, "GET", path, 0)
		if w.Code != 200 {
			t.Fatalf("page %d: %d %s", page, w.Code, w.Body)
		}
		p := decode[spotPage](t, w)
		for _, s := range p.Items {
			if s.Tags == nil {
				t.Fatalf("tags must be an array: %s", w.Body)
			}
			got = append(got, s.ID)
		}
		if p.NextCursor == nil {
			break
		}
		cursor = *p.NextCursor
	}
	want := []uint64{ids[4], ids[3], ids[1], ids[0]}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("got %v, want %v", got, want)
	}

	if w := do(t, h, "GET", fmt.Sprintf("/users/%d/spots?cursor=!!", u), 0); w.Code != 400 {
		t.Fatalf("bad cursor: %d", w.Code)
	}
	if w := do(t, h, "GET", fmt.Sprintf("/users/%d/spots?limit=0", u), 0); w.Code != 400 {
		t.Fatalf("bad limit: %d", w.Code)
	}
	empty := testutil.NewUser(t, db)
	if w := do(t, h, "GET", fmt.Sprintf("/users/%d/spots", empty), 0); w.Code != 200 ||
		w.Body.String() != `{"items":[],"next_cursor":null}`+"\n" {
		t.Fatalf("empty: %d %q", w.Code, w.Body)
	}
}

func TestUserUpdatesPaging(t *testing.T) {
	db, h := setup(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, other, "theirs")
	hiddenSpot := newSpot(t, db, other, "hidden")
	exec(t, db, `UPDATE spots SET status = 'hidden' WHERE id = ?`, hiddenSpot)
	var ids []uint64
	for i := 0; i < 4; i++ {
		ids = append(ids, newUpdate(t, db, s, u, fmt.Sprintf("u%d", i)))
	}
	exec(t, db, `UPDATE spot_updates SET status = 'hidden' WHERE id = ?`, ids[1])
	newUpdate(t, db, hiddenSpot, u, "on a hidden spot")
	newUpdate(t, db, s, other, "not mine")

	var got []uint64
	cursor := ""
	for page := 0; ; page++ {
		path := fmt.Sprintf("/users/%d/updates?limit=2", u)
		if cursor != "" {
			path += "&cursor=" + cursor
		}
		w := do(t, h, "GET", path, 0)
		if w.Code != 200 {
			t.Fatalf("page %d: %d %s", page, w.Code, w.Body)
		}
		p := decode[updatePage](t, w)
		for _, it := range p.Items {
			if it.Author.ID != u || it.Spot.ID != s || it.Photos == nil {
				t.Fatalf("item: %s", w.Body)
			}
			got = append(got, it.ID)
		}
		if p.NextCursor == nil {
			break
		}
		cursor = *p.NextCursor
	}
	// Same timestamps: newest id first.
	want := []uint64{ids[3], ids[2], ids[0]}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	if w := do(t, h, "GET", fmt.Sprintf("/users/%d/updates?cursor=nope", u), 0); w.Code != 400 {
		t.Fatalf("bad cursor: %d", w.Code)
	}
}

func TestBio(t *testing.T) {
	db, h := setup(t)
	me, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	put := func(user uint64, body string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest("PUT", "/me/bio", strings.NewReader(body))
		if user != 0 {
			req.Header.Set("Authorization", "Bearer "+testutil.Token(t, user))
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		return w
	}
	type bioProfile struct {
		Bio string `json:"bio"`
	}
	bioOf := func(id uint64) string {
		w := do(t, h, "GET", fmt.Sprintf("/users/%d", id), 0)
		return decode[bioProfile](t, w).Bio
	}
	if got := bioOf(me); got != "" {
		t.Fatalf("new users have no bio: %q", got)
	}
	if w := put(0, `{"bio":"x"}`); w.Code != 401 {
		t.Fatalf("anonymous: %d", w.Code)
	}
	for _, body := range []string{`{}`, `{"bio":null}`, `{"bio":5}`, `nope`} {
		if w := put(me, body); w.Code != 400 {
			t.Errorf("%s: %d", body, w.Code)
		}
	}
	if w := put(me, `{"bio":"`+strings.Repeat("a", 301)+`"}`); w.Code != 400 {
		t.Fatalf("too long: %d", w.Code)
	}

	w := put(me, `{"bio":"  Chille gern am Isarufer.\r\n\r\n\r\nGrüße  "}`)
	if w.Code != 200 {
		t.Fatalf("set: %d %s", w.Code, w.Body)
	}
	const want = "Chille gern am Isarufer.\n\nGrüße"
	if got := decode[bioProfile](t, w).Bio; got != want {
		t.Fatalf("answer %q", got)
	}
	if got := bioOf(me); got != want {
		t.Fatalf("profile %q", got)
	}
	if got := bioOf(other); got != "" {
		t.Fatalf("someone else's bio changed: %q", got)
	}
	// the same again changes no row, and is still fine
	if w := put(me, `{"bio":"`+strings.ReplaceAll(want, "\n", `\n`)+`"}`); w.Code != 200 {
		t.Fatalf("unchanged: %d %s", w.Code, w.Body)
	}
	if w := put(me, `{"bio":""}`); w.Code != 200 || bioOf(me) != "" {
		t.Fatalf("clear: %d, %q", w.Code, bioOf(me))
	}
	exec(t, db, `UPDATE users SET banned_at = NOW() WHERE id = ?`, other)
	if w := put(other, `{"bio":"still here"}`); w.Code == 200 {
		t.Fatalf("banned user set a bio")
	}
}
