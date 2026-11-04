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
	UpdateID  uint64 `json:"update_id"`
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

func post(t *testing.T, h http.Handler, user, update uint64, body string) (*httptest.ResponseRecorder, comment) {
	t.Helper()
	b, _ := json.Marshal(map[string]string{"body": body})
	w := do(t, h, "POST", fmt.Sprintf("/updates/%d/comments", update), user, string(b))
	var c comment
	_ = json.Unmarshal(w.Body.Bytes(), &c)
	return w, c
}

func list(t *testing.T, h http.Handler, user, update uint64, query string) (*httptest.ResponseRecorder, page) {
	t.Helper()
	w := do(t, h, "GET", fmt.Sprintf("/updates/%d/comments%s", update, query), user, "")
	var p page
	_ = json.Unmarshal(w.Body.Bytes(), &p)
	return w, p
}

func TestPostAndListOldestFirst(t *testing.T) {
	db, h := setup(t)
	alice, bob := testutil.NewUser(t, db), testutil.NewUser(t, db)
	up := newUpdate(t, db, newSpot(t, db, alice), alice)

	w, c := post(t, h, bob, up, "  first!  ")
	if w.Code != http.StatusCreated {
		t.Fatalf("post: %d %s", w.Code, w.Body)
	}
	if c.Body != "first!" || !c.Mine || c.Author.ID != bob || c.UpdateID != up || c.Author.DisplayName == "" {
		t.Fatalf("created %+v", c)
	}
	if w, _ := post(t, h, alice, up, "second"); w.Code != http.StatusCreated {
		t.Fatalf("post 2: %d", w.Code)
	}

	// anonymous: both, oldest first, none mine
	w, p := list(t, h, 0, up, "")
	if w.Code != 200 || len(p.Items) != 2 || p.NextCursor != nil {
		t.Fatalf("list: %d %s", w.Code, w.Body)
	}
	if p.Items[0].Body != "first!" || p.Items[1].Body != "second" || p.Items[0].Mine || p.Items[1].Mine {
		t.Fatalf("order/mine: %+v", p.Items)
	}
	// as bob: only his own is mine
	_, p = list(t, h, bob, up, "")
	if !p.Items[0].Mine || p.Items[1].Mine {
		t.Fatalf("mine: %+v", p.Items)
	}
}

func TestPaging(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	up := newUpdate(t, db, newSpot(t, db, u), u)
	for i := 0; i < 5; i++ {
		if w, _ := post(t, h, u, up, fmt.Sprintf("c%d", i)); w.Code != 201 {
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
		w, p := list(t, h, 0, up, q)
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
	if strings.Join(got, ",") != "c0,c1,c2,c3,c4" {
		t.Fatalf("paged: %v", got)
	}
	if w, _ := list(t, h, 0, up, "?cursor=nope"); w.Code != 400 {
		t.Fatalf("bad cursor: %d", w.Code)
	}
	if w, _ := list(t, h, 0, up, "?limit=0"); w.Code != 400 {
		t.Fatalf("bad limit: %d", w.Code)
	}
}

func TestPostValidation(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	up := newUpdate(t, db, newSpot(t, db, u), u)

	if w, _ := post(t, h, 0, up, "hi"); w.Code != 401 {
		t.Fatalf("anonymous: %d", w.Code)
	}
	for _, body := range []string{"", "   \n ", strings.Repeat("x", 501)} {
		if w, _ := post(t, h, u, up, body); w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_body") {
			t.Fatalf("body %q: %d %s", body, w.Code, w.Body)
		}
	}
	// 500 characters (runes, not bytes) is fine
	if w, _ := post(t, h, u, up, strings.Repeat("ü", 500)); w.Code != 201 {
		t.Fatalf("500 runes: %d %s", w.Code, w.Body)
	}
	if w := do(t, h, "POST", fmt.Sprintf("/updates/%d/comments", up), u, "{"); w.Code != 400 {
		t.Fatalf("bad json: %d", w.Code)
	}
}

func TestInvisibleUpdateIs404(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	spot := newSpot(t, db, u)
	hidden := newUpdate(t, db, spot, u)
	if _, err := db.Exec(`UPDATE spot_updates SET status = 'hidden' WHERE id = ?`, hidden); err != nil {
		t.Fatal(err)
	}
	hiddenSpot := newSpot(t, db, u)
	onHiddenSpot := newUpdate(t, db, hiddenSpot, u)
	if _, err := db.Exec(`UPDATE spots SET status = 'hidden' WHERE id = ?`, hiddenSpot); err != nil {
		t.Fatal(err)
	}
	for _, id := range []uint64{hidden, onHiddenSpot, 99999} {
		if w, _ := post(t, h, u, id, "hi"); w.Code != 404 {
			t.Fatalf("post on %d: %d", id, w.Code)
		}
		if w, _ := list(t, h, u, id, ""); w.Code != 404 {
			t.Fatalf("list on %d: %d", id, w.Code)
		}
	}
	if w := do(t, h, "GET", "/updates/abc/comments", 0, ""); w.Code != 404 {
		t.Fatalf("bad id: %d", w.Code)
	}
}

func TestHiddenCommentsAreNotListed(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	up := newUpdate(t, db, newSpot(t, db, u), u)
	_, c := post(t, h, u, up, "bad")
	post(t, h, u, up, "good")
	if _, err := db.Exec(`UPDATE comments SET status = 'hidden' WHERE id = ?`, c.ID); err != nil {
		t.Fatal(err)
	}
	_, p := list(t, h, 0, up, "")
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
	up := newUpdate(t, db, newSpot(t, db, author), author)
	_, c1 := post(t, h, author, up, "one")
	_, c2 := post(t, h, author, up, "two")
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
	if _, p := list(t, h, 0, up, ""); len(p.Items) != 0 {
		t.Fatalf("left: %+v", p.Items)
	}
}

func TestQuota(t *testing.T) {
	db, h := setupWith(t, quotas.Config{CommentsPerDay: 2})
	u := testutil.NewUser(t, db)
	up := newUpdate(t, db, newSpot(t, db, u), u)
	// invalid bodies do not use up the quota
	post(t, h, u, up, "")
	for i := 0; i < 2; i++ {
		if w, _ := post(t, h, u, up, "ok"); w.Code != 201 {
			t.Fatalf("post %d: %d", i, w.Code)
		}
	}
	if w, _ := post(t, h, u, up, "one too many"); w.Code != 429 || !strings.Contains(w.Body.String(), "quota_exceeded") {
		t.Fatalf("quota: %d %s", w.Code, w.Body)
	}
}

func TestCommentsGoWithTheirUpdateAndAuthor(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	up := newUpdate(t, db, newSpot(t, db, a), a)
	post(t, h, a, up, "by a")
	post(t, h, b, up, "by b")
	if _, err := db.Exec(`DELETE FROM users WHERE id = ?`, b); err != nil {
		t.Fatal(err)
	}
	if _, p := list(t, h, 0, up, ""); len(p.Items) != 1 || p.Items[0].Body != "by a" {
		t.Fatalf("after user delete: %+v", p.Items)
	}
	if _, err := db.Exec(`DELETE FROM spot_updates WHERE id = ?`, up); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM comments`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("comments left: %d %v", n, err)
	}
}
