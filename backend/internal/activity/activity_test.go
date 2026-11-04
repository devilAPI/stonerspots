package activity_test

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

	"stonerspots/backend/internal/activity"
	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/comments"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/engagement"
	"stonerspots/backend/internal/reviews"
	"stonerspots/backend/internal/testutil"
	"stonerspots/backend/internal/users"
)

type item struct {
	ID        uint64    `json:"id"`
	Kind      string    `json:"kind"`
	CreatedAt time.Time `json:"created_at"`
	Read      bool      `json:"read"`
	Actor     struct {
		ID          uint64 `json:"id"`
		DisplayName string `json:"display_name"`
	} `json:"actor"`
	Spot *struct {
		ID    uint64 `json:"id"`
		Title string `json:"title"`
	} `json:"spot"`
	UpdateID       *uint64 `json:"update_id"`
	CommentID      *uint64 `json:"comment_id"`
	CommentPreview *string `json:"comment_preview"`
}

type page struct {
	Items      []item  `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	d := app.Deps{DB: db, Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://test",
	}}
	r := chi.NewRouter()
	auth.MountWithOptions(r, d, auth.MountOptions{DisablePoW: true, UnreadActivity: activity.UnreadCounter(db)})
	users.Mount(r, d)
	comments.Mount(r, d, nil)
	engagement.Mount(r, d, nil)
	reviews.Mount(r, d, nil)
	activity.Mount(r, d)
	return db, r
}

func exec(t *testing.T, db *sql.DB, q string, args ...any) uint64 {
	t.Helper()
	res, err := db.Exec(q, args...)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func newSpot(t *testing.T, db *sql.DB, owner uint64, title string) uint64 {
	t.Helper()
	return exec(t, db, `INSERT INTO spots (user_id, title, description, location)
		VALUES (?, ?, 'd', ST_GeomFromText('POINT(10 50)'))`, owner, title)
}

func newUpdate(t *testing.T, db *sql.DB, spot, owner uint64) uint64 {
	t.Helper()
	return exec(t, db, `INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'u')`, spot, owner)
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

func must(t *testing.T, w *httptest.ResponseRecorder, code int) {
	t.Helper()
	if w.Code != code {
		t.Fatalf("want %d, got %d %s", code, w.Code, w.Body)
	}
}

func list(t *testing.T, h http.Handler, user uint64, query string) page {
	t.Helper()
	w := do(t, h, "GET", "/me/activity"+query, user, "")
	must(t, w, 200)
	var p page
	if err := json.Unmarshal(w.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	return p
}

func unread(t *testing.T, h http.Handler, user uint64) int {
	t.Helper()
	w := do(t, h, "GET", "/me", user, "")
	must(t, w, 200)
	var me struct {
		ID             uint64 `json:"id"`
		UnreadActivity *int   `json:"unread_activity"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &me); err != nil {
		t.Fatal(err)
	}
	if me.ID != user || me.UnreadActivity == nil {
		t.Fatalf("/me: %s", w.Body)
	}
	return *me.UnreadActivity
}

func TestFollowNotifiesAndUnfollowTakesItBack(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)

	must(t, do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", a), b, ""), 204)
	must(t, do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", a), b, ""), 204) // idempotent: no second row
	p := list(t, h, a, "")
	if len(p.Items) != 1 || p.Items[0].Kind != "follow" || p.Items[0].Actor.ID != b || p.Items[0].Read ||
		p.Items[0].Spot != nil || p.Items[0].UpdateID != nil || p.Items[0].CommentPreview != nil || p.NextCursor != nil {
		t.Fatalf("after follow: %+v", p)
	}
	if p.Items[0].Actor.DisplayName == "" || p.Items[0].CreatedAt.IsZero() {
		t.Fatalf("actor/created_at missing: %+v", p.Items[0])
	}
	if n := unread(t, h, a); n != 1 {
		t.Fatalf("unread = %d, want 1", n)
	}
	if n := len(list(t, h, b, "").Items); n != 0 {
		t.Fatalf("the follower got %d items", n)
	}

	// toggling does not spam
	must(t, do(t, h, "DELETE", fmt.Sprintf("/users/%d/follow", a), b, ""), 204)
	if n := len(list(t, h, a, "").Items); n != 0 {
		t.Fatalf("after unfollow: %d items", n)
	}
	must(t, do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", a), b, ""), 204)
	if n := unread(t, h, a); n != 1 {
		t.Fatalf("after re-follow unread = %d", n)
	}

	// a notice already read stays when the follow goes
	must(t, do(t, h, "POST", "/me/activity/read", a, ""), 200)
	must(t, do(t, h, "DELETE", fmt.Sprintf("/users/%d/follow", a), b, ""), 204)
	p = list(t, h, a, "")
	if len(p.Items) != 1 || !p.Items[0].Read {
		t.Fatalf("read notice after unfollow: %+v", p)
	}
}

func TestCommentNotifiesUpdateAuthor(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	spot := newSpot(t, db, a, "Bank am See")
	upd := newUpdate(t, db, spot, a)

	long := strings.Repeat("ä", 119) + "xyz"
	w := do(t, h, "POST", fmt.Sprintf("/updates/%d/comments", upd), b, fmt.Sprintf(`{"body":%q}`, long))
	must(t, w, 201)
	var c struct {
		ID uint64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &c)
	// commenting on your own update notifies nobody
	must(t, do(t, h, "POST", fmt.Sprintf("/updates/%d/comments", upd), a, `{"body":"mine"}`), 201)

	p := list(t, h, a, "")
	if len(p.Items) != 1 {
		t.Fatalf("items: %+v", p)
	}
	it := p.Items[0]
	if it.Kind != "comment" || it.Actor.ID != b || it.Spot == nil || it.Spot.ID != spot || it.Spot.Title != "Bank am See" ||
		it.UpdateID == nil || *it.UpdateID != upd || it.CommentID == nil || *it.CommentID != c.ID || it.CommentPreview == nil {
		t.Fatalf("comment item: %+v", it)
	}
	if want := strings.Repeat("ä", 119) + "x"; *it.CommentPreview != want {
		t.Fatalf("preview %q, want %q", *it.CommentPreview, want)
	}

	// a hidden comment is no longer shown or counted
	exec(t, db, `UPDATE comments SET status = 'hidden' WHERE id = ?`, c.ID)
	if n := len(list(t, h, a, "").Items); n != 0 {
		t.Fatalf("hidden comment still listed")
	}
	if n := unread(t, h, a); n != 0 {
		t.Fatalf("hidden comment counted: %d", n)
	}
	// a deleted comment takes its row with it
	exec(t, db, `UPDATE comments SET status = 'active' WHERE id = ?`, c.ID)
	must(t, do(t, h, "DELETE", fmt.Sprintf("/comments/%d", c.ID), b, ""), 204)
	var rows int
	if err := db.QueryRow(`SELECT COUNT(*) FROM activity`).Scan(&rows); err != nil || rows != 0 {
		t.Fatalf("rows after delete: %d %v", rows, err)
	}
}

func TestLikeNotifiesAndUnlikeTakesItBack(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	spot := newSpot(t, db, a, "Aussicht")

	must(t, do(t, h, "PUT", fmt.Sprintf("/spots/%d/like", spot), b, ""), 200)
	must(t, do(t, h, "PUT", fmt.Sprintf("/spots/%d/like", spot), b, ""), 200)
	must(t, do(t, h, "PUT", fmt.Sprintf("/spots/%d/like", spot), a, ""), 200) // own spot: nothing
	p := list(t, h, a, "")
	if len(p.Items) != 1 || p.Items[0].Kind != "like" || p.Items[0].Actor.ID != b ||
		p.Items[0].Spot == nil || p.Items[0].Spot.Title != "Aussicht" || p.Items[0].CommentPreview != nil {
		t.Fatalf("like items: %+v", p)
	}
	for range 3 {
		must(t, do(t, h, "DELETE", fmt.Sprintf("/spots/%d/like", spot), b, ""), 200)
		must(t, do(t, h, "PUT", fmt.Sprintf("/spots/%d/like", spot), b, ""), 200)
	}
	if n := unread(t, h, a); n != 1 {
		t.Fatalf("after toggling unread = %d, want 1", n)
	}
	must(t, do(t, h, "DELETE", fmt.Sprintf("/spots/%d/like", spot), b, ""), 200)
	if n := unread(t, h, a); n != 0 {
		t.Fatalf("after unlike unread = %d", n)
	}
}

func TestReviewNotifiesOnlyOnCreation(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	spot := newSpot(t, db, a, "Wald")
	path := fmt.Sprintf("/spots/%d/review", spot)

	must(t, do(t, h, "PUT", path, b, `{"rating":4,"body":"gut"}`), 200)
	must(t, do(t, h, "PUT", path, b, `{"rating":5,"body":"sehr gut"}`), 200) // edit
	must(t, do(t, h, "PUT", path, b, `{"rating":5,"body":"sehr gut"}`), 200) // unchanged
	p := list(t, h, a, "")
	if len(p.Items) != 1 || p.Items[0].Kind != "review" || p.Items[0].Spot == nil || p.Items[0].Spot.ID != spot {
		t.Fatalf("review items: %+v", p)
	}

	// deleting and rating again leaves one notice
	must(t, do(t, h, "DELETE", path, b, ""), 204)
	if n := unread(t, h, a); n != 0 {
		t.Fatalf("after delete unread = %d", n)
	}
	must(t, do(t, h, "PUT", path, b, `{"rating":3}`), 200)
	if n := unread(t, h, a); n != 1 {
		t.Fatalf("after new review unread = %d", n)
	}

	// a hidden review is skipped
	exec(t, db, `UPDATE spot_reviews SET status = 'hidden' WHERE spot_id = ?`, spot)
	if n := len(list(t, h, a, "").Items); n != 0 {
		t.Fatalf("hidden review listed")
	}
}

func TestSkipsBannedActorsAndHiddenSpots(t *testing.T) {
	db, h := setup(t)
	a, b, c := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	spot := newSpot(t, db, a, "x")
	must(t, do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", a), b, ""), 204)
	must(t, do(t, h, "PUT", fmt.Sprintf("/spots/%d/like", spot), c, ""), 200)
	if n := unread(t, h, a); n != 2 {
		t.Fatalf("unread = %d, want 2", n)
	}

	exec(t, db, `UPDATE users SET banned_at = NOW() WHERE id = ?`, b)
	p := list(t, h, a, "")
	if len(p.Items) != 1 || p.Items[0].Actor.ID != c {
		t.Fatalf("banned actor listed: %+v", p)
	}
	exec(t, db, `UPDATE spots SET status = 'hidden' WHERE id = ?`, spot)
	if n := len(list(t, h, a, "").Items); n != 0 {
		t.Fatalf("hidden spot listed")
	}
	if n := unread(t, h, a); n != 0 {
		t.Fatalf("unread = %d, want 0", n)
	}
}

func TestPagingAndMarkRead(t *testing.T) {
	db, h := setup(t)
	a := testutil.NewUser(t, db)
	var ids []uint64
	for range 5 {
		f := testutil.NewUser(t, db)
		must(t, do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", a), f, ""), 204)
	}
	var seen []item
	query := "?limit=2"
	for pages := 0; ; pages++ {
		if pages > 5 {
			t.Fatal("paging does not end")
		}
		p := list(t, h, a, query)
		seen = append(seen, p.Items...)
		if p.NextCursor == nil {
			break
		}
		query = "?limit=2&cursor=" + *p.NextCursor
	}
	if len(seen) != 5 {
		t.Fatalf("paged %d items, want 5", len(seen))
	}
	for i, it := range seen {
		if i > 0 && it.ID >= seen[i-1].ID {
			t.Fatalf("not newest first: %+v", seen)
		}
		ids = append(ids, it.ID)
	}

	// up_to marks that row and everything older
	must(t, do(t, h, "POST", "/me/activity/read", a, fmt.Sprintf(`{"up_to":%d}`, ids[2])), 200)
	if n := unread(t, h, a); n != 2 {
		t.Fatalf("unread after up_to = %d, want 2", n)
	}
	p := list(t, h, a, "")
	for i, it := range p.Items {
		if it.Read != (i >= 2) {
			t.Fatalf("read flags: %+v", p.Items)
		}
	}
	// someone else cannot mark a's rows
	other := testutil.NewUser(t, db)
	must(t, do(t, h, "POST", "/me/activity/read", other, "{}"), 200)
	if n := unread(t, h, a); n != 2 {
		t.Fatalf("other user marked rows read")
	}
	w := do(t, h, "POST", "/me/activity/read", a, "{}")
	must(t, w, 200)
	if !strings.Contains(w.Body.String(), `"unread_activity":0`) {
		t.Fatalf("read response: %s", w.Body)
	}
	if n := unread(t, h, a); n != 0 {
		t.Fatalf("unread after all = %d", n)
	}

	must(t, do(t, h, "GET", "/me/activity?cursor=!!!", a, ""), 400)
	must(t, do(t, h, "GET", "/me/activity?limit=0", a, ""), 400)
	must(t, do(t, h, "POST", "/me/activity/read", a, "nope"), 400)
	must(t, do(t, h, "GET", "/me/activity", 0, ""), 401)
	must(t, do(t, h, "POST", "/me/activity/read", 0, ""), 401)
}

func TestDeletingActorRemovesRows(t *testing.T) {
	db, h := setup(t)
	a, b := testutil.NewUser(t, db), testutil.NewUser(t, db)
	must(t, do(t, h, "PUT", fmt.Sprintf("/users/%d/follow", a), b, ""), 204)
	exec(t, db, `DELETE FROM users WHERE id = ?`, b)
	if n := unread(t, h, a); n != 0 {
		t.Fatalf("unread = %d", n)
	}
}
