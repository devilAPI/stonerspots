package comments_test

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/comments"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/testutil"
)

func setupWith(t *testing.T, q quotas.Config) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	comments.Mount(r, app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}}, quotas.NewTracker(q))
	return db, r
}

func setup(t *testing.T) (*sql.DB, http.Handler) {
	return setupWith(t, quotas.Config{})
}

func newSpot(t *testing.T, db *sql.DB, owner uint64) uint64 {
	t.Helper()
	res, err := db.Exec(`INSERT INTO spots (user_id, title, description, location)
		VALUES (?, 's', 'd', ST_GeomFromText('POINT(10 50)'))`, owner)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func newUpdate(t *testing.T, db *sql.DB, spot, owner uint64) uint64 {
	t.Helper()
	res, err := db.Exec(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'b')`, spot, owner)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func do(t *testing.T, h http.Handler, method, path string, user uint64, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if user != 0 {
		req.Header.Set("Authorization", "Bearer "+testutil.Token(t, user))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

type comment struct {
	ID        uint64 `json:"id"`
	SpotID    uint64 `json:"spot_id"`
	Body      string `json:"body"`
	CreatedAt string `json:"created_at"`
	Author    struct {
		ID          uint64 `json:"id"`
		DisplayName string `json:"display_name"`
	} `json:"author"`
	Mine bool `json:"mine"`
}

type page struct {
	Items      []comment `json:"items"`
	NextCursor *string   `json:"next_cursor"`
}

func post(t *testing.T, h http.Handler, user, spot uint64, body string) (*httptest.ResponseRecorder, comment) {
	t.Helper()
	b, _ := json.Marshal(map[string]string{"body": body})
	w := do(t, h, "POST", fmt.Sprintf("/spots/%d/comments", spot), user, string(b))
	var c comment
	_ = json.Unmarshal(w.Body.Bytes(), &c)
	return w, c
}

func list(t *testing.T, h http.Handler, user, spot uint64, query string) (*httptest.ResponseRecorder, page) {
	t.Helper()
	w := do(t, h, "GET", fmt.Sprintf("/spots/%d/comments%s", spot, query), user, "")
	var p page
	_ = json.Unmarshal(w.Body.Bytes(), &p)
	return w, p
}

func TestPostAndListNewestFirst(t *testing.T) {
	db, h := setup(t)
	alice, bob := testutil.NewUser(t, db), testutil.NewUser(t, db)
	spot := newSpot(t, db, alice)

	w, c := post(t, h, bob, spot, "  first!  ")
	if w.Code != http.StatusCreated {
		t.Fatalf("post: %d %s", w.Code, w.Body)
	}
	if c.Body != "first!" || !c.Mine || c.Author.ID != bob || c.SpotID != spot || c.Author.DisplayName == "" {
		t.Fatalf("created %+v", c)
	}
	if w, _ := post(t, h, alice, spot, "second"); w.Code != http.StatusCreated {
		t.Fatalf("post 2: %d", w.Code)
	}

	// anonymous: both, newest first, none mine
	w, p := list(t, h, 0, spot, "")
	if w.Code != 200 || len(p.Items) != 2 || p.NextCursor != nil {
		t.Fatalf("list: %d %s", w.Code, w.Body)
	}
	if p.Items[0].Body != "second" || p.Items[1].Body != "first!" || p.Items[0].Mine || p.Items[1].Mine {
		t.Fatalf("order/mine: %+v", p.Items)
	}
	// as bob: only his own is mine
	_, p = list(t, h, bob, spot, "")
	if p.Items[0].Mine || !p.Items[1].Mine {
		t.Fatalf("mine: %+v", p.Items)
	}
	// another spot's comments stay apart
	if _, p := list(t, h, 0, newSpot(t, db, alice), ""); len(p.Items) != 0 {
		t.Fatalf("other spot: %+v", p.Items)
	}
}

// Spots without updates take comments too: they belong to the spot.
func TestSpotWithoutUpdatesTakesComments(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	spot := newSpot(t, db, u)
	if w, _ := post(t, h, u, spot, "hi"); w.Code != 201 {
		t.Fatalf("post: %d %s", w.Code, w.Body)
	}
}

func TestPaging(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	spot := newSpot(t, db, u)
	for i := 0; i < 5; i++ {
		if w, _ := post(t, h, u, spot, fmt.Sprintf("c%d", i)); w.Code != 201 {
			t.Fatalf("post %d: %d", i, w.Code)
		}
	}
	var got []string
	cursor := ""
	for pages := 0; pages < 5; pages++ {
		q := "?limit=2"
		if cursor != "" {
			q += "&cursor=" + cursor
		}
		w, p := list(t, h, 0, spot, q)
		if w.Code != 200 {
			t.Fatalf("page: %d %s", w.Code, w.Body)
		}
		for _, c := range p.Items {
			got = append(got, c.Body)
		}
		if p.NextCursor == nil {
			break
		}
		cursor = *p.NextCursor
	}
	if strings.Join(got, ",") != "c4,c3,c2,c1,c0" {
		t.Fatalf("paged: %v", got)
	}
	if w, _ := list(t, h, 0, spot, "?cursor=nope"); w.Code != 400 {
		t.Fatalf("bad cursor: %d", w.Code)
	}
	if w, _ := list(t, h, 0, spot, "?limit=0"); w.Code != 400 {
		t.Fatalf("bad limit: %d", w.Code)
	}
}

func TestPostValidation(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	spot := newSpot(t, db, u)

	if w, _ := post(t, h, 0, spot, "hi"); w.Code != 401 {
		t.Fatalf("anonymous: %d", w.Code)
	}
	for _, body := range []string{"", "   \n ", strings.Repeat("x", 501)} {
		if w, _ := post(t, h, u, spot, body); w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_body") {
			t.Fatalf("body %q: %d %s", body, w.Code, w.Body)
		}
	}
	// 500 characters (runes, not bytes) is fine
	if w, _ := post(t, h, u, spot, strings.Repeat("ü", 500)); w.Code != 201 {
		t.Fatalf("500 runes: %d %s", w.Code, w.Body)
	}
	if w := do(t, h, "POST", fmt.Sprintf("/spots/%d/comments", spot), u, "{"); w.Code != 400 {
		t.Fatalf("bad json: %d", w.Code)
	}
}

func TestInactiveSpotIs404(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	hidden := newSpot(t, db, u)
	if _, err := db.Exec(`UPDATE spots SET status = 'hidden' WHERE id = ?`, hidden); err != nil {
		t.Fatal(err)
	}
	for _, id := range []uint64{hidden, 99999} {
		if w, _ := post(t, h, u, id, "hi"); w.Code != 404 {
			t.Fatalf("post on %d: %d", id, w.Code)
		}
		if w, _ := list(t, h, u, id, ""); w.Code != 404 {
			t.Fatalf("list on %d: %d", id, w.Code)
		}
	}
	if w := do(t, h, "GET", "/spots/abc/comments", 0, ""); w.Code != 404 {
		t.Fatalf("bad id: %d", w.Code)
	}
}

// Like updates, a locked spot takes new comments from admins only; its
// comments can still be read.
func TestLockedSpot(t *testing.T) {
	db, h := setup(t)
	owner, admin := testutil.NewUser(t, db), testutil.NewUser(t, db)
	if _, err := db.Exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, admin); err != nil {
		t.Fatal(err)
	}
	spot := newSpot(t, db, owner)
	post(t, h, owner, spot, "before")
	if _, err := db.Exec(`UPDATE spots SET locked = 1 WHERE id = ?`, spot); err != nil {
		t.Fatal(err)
	}
	if w, _ := post(t, h, owner, spot, "after"); w.Code != 403 || !strings.Contains(w.Body.String(), "spot_locked") {
		t.Fatalf("locked, owner: %d %s", w.Code, w.Body)
	}
	if w, _ := post(t, h, admin, spot, "admin"); w.Code != 201 {
		t.Fatalf("locked, admin: %d %s", w.Code, w.Body)
	}
	if _, p := list(t, h, 0, spot, ""); len(p.Items) != 2 {
		t.Fatalf("list: %+v", p.Items)
	}
}

func TestHiddenCommentsAreNotListed(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	spot := newSpot(t, db, u)
	_, c := post(t, h, u, spot, "bad")
	post(t, h, u, spot, "good")
	if _, err := db.Exec(`UPDATE comments SET status = 'hidden' WHERE id = ?`, c.ID); err != nil {
		t.Fatal(err)
	}
	_, p := list(t, h, 0, spot, "")
	if len(p.Items) != 1 || p.Items[0].Body != "good" {
		t.Fatalf("got %+v", p.Items)
	}
}

func TestDelete(t *testing.T) {
	db, h := setup(t)
	author, other, admin := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	if _, err := db.Exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, admin); err != nil {
		t.Fatal(err)
	}
	spot := newSpot(t, db, author)
	_, c1 := post(t, h, author, spot, "one")
	_, c2 := post(t, h, author, spot, "two")
	if _, err := db.Exec(`INSERT INTO reports (user_id, target_type, target_id) VALUES (?, 'comment', ?)`, other, c1.ID); err != nil {
		t.Fatal(err)
	}

	if w := do(t, h, "DELETE", fmt.Sprintf("/comments/%d", c1.ID), 0, ""); w.Code != 401 {
		t.Fatalf("anonymous: %d", w.Code)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/comments/%d", c1.ID), other, ""); w.Code != 404 {
		t.Fatalf("someone else: %d", w.Code)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/comments/%d", c1.ID), author, ""); w.Code != 204 {
		t.Fatalf("author: %d %s", w.Code, w.Body)
	}
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM reports WHERE target_type = 'comment' AND target_id = ?`, c1.ID).Scan(&n); err != nil || n != 0 {
		t.Fatalf("reports left: %d %v", n, err)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/comments/%d", c1.ID), author, ""); w.Code != 404 {
		t.Fatalf("again: %d", w.Code)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/comments/%d", c2.ID), admin, ""); w.Code != 204 {
		t.Fatalf("admin: %d", w.Code)
	}
	if _, p := list(t, h, 0, spot, ""); len(p.Items) != 0 {
		t.Fatalf("left: %+v", p.Items)
	}
}

func TestQuota(t *testing.T) {
	db, h := setupWith(t, quotas.Config{CommentsPerDay: 2})
	u := testutil.NewUser(t, db)
	spot := newSpot(t, db, u)
	// invalid bodies do not use up the quota
	post(t, h, u, spot, "")
	for i := 0; i < 2; i++ {
		if w, _ := post(t, h, u, spot, "ok"); w.Code != 201 {
			t.Fatalf("post %d: %d", i, w.Code)
		}
	}
	if w, _ := post(t, h, u, spot, "one too many"); w.Code != 429 || !strings.Contains(w.Body.String(), "quota_exceeded") {
		t.Fatalf("quota: %d %s", w.Code, w.Body)
	}
}

// Comments outlive the spot's updates, and go with their spot and author.
func TestCommentsGoWithTheirSpotAndAuthor(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	spot := newSpot(t, db, a)
	up := newUpdate(t, db, spot, a)
	post(t, h, a, spot, "by a")
	post(t, h, b, spot, "by b")
	if _, err := db.Exec(`DELETE FROM users WHERE id = ?`, b); err != nil {
		t.Fatal(err)
	}
	if _, p := list(t, h, 0, spot, ""); len(p.Items) != 1 || p.Items[0].Body != "by a" {
		t.Fatalf("after user delete: %+v", p.Items)
	}
	if _, err := db.Exec(`DELETE FROM spot_updates WHERE id = ?`, up); err != nil {
		t.Fatal(err)
	}
	if _, p := list(t, h, 0, spot, ""); len(p.Items) != 1 {
		t.Fatalf("after update delete: %+v", p.Items)
	}
	if _, err := db.Exec(`DELETE FROM spots WHERE id = ?`, spot); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM comments`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("comments left: %d %v", n, err)
	}
}
