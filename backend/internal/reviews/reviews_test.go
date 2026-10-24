package reviews_test

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
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/engagement"
	"stonerspots/backend/internal/reviews"
	"stonerspots/backend/internal/testutil"
)

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	d := app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}}
	reviews.Mount(r, d)
	engagement.Mount(r, d)
	return db, r
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

type review struct {
	ID        uint64 `json:"id"`
	Rating    int    `json:"rating"`
	Body      string `json:"body"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
	Author    struct {
		ID          uint64 `json:"id"`
		DisplayName string `json:"display_name"`
	} `json:"author"`
}

type listResp struct {
	Summary struct {
		Avg          float64        `json:"avg"`
		Count        int            `json:"count"`
		Distribution map[string]int `json:"distribution"`
	} `json:"summary"`
	Mine       *review  `json:"mine"`
	Items      []review `json:"items"`
	NextCursor *string  `json:"next_cursor"`
}

func put(t *testing.T, h http.Handler, user, spot uint64, body string) (*httptest.ResponseRecorder, review) {
	t.Helper()
	w := do(t, h, "PUT", fmt.Sprintf("/spots/%d/review", spot), user, body)
	var r review
	_ = json.Unmarshal(w.Body.Bytes(), &r)
	return w, r
}

func list(t *testing.T, h http.Handler, user, spot uint64, q string) (int, listResp) {
	t.Helper()
	w := do(t, h, "GET", fmt.Sprintf("/spots/%d/reviews%s", spot, q), user, "")
	var l listResp
	_ = json.Unmarshal(w.Body.Bytes(), &l)
	return w.Code, l
}

func TestPutCreatesThenEdits(t *testing.T) {
	db, h := setup(t)
	owner, u := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	w, r1 := put(t, h, u, s, `{"rating":4,"body":"  nice place  "}`)
	if w.Code != 200 || r1.Rating != 4 || r1.Body != "nice place" || r1.Author.ID != u || r1.Author.DisplayName == "" || r1.ID == 0 || r1.CreatedAt == "" || r1.UpdatedAt == "" {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	w, r2 := put(t, h, u, s, `{"rating":2}`)
	if w.Code != 200 || r2.ID != r1.ID || r2.Rating != 2 || r2.Body != "" {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	var n int
	db.QueryRow(`SELECT COUNT(*) FROM spot_reviews`).Scan(&n)
	if n != 1 {
		t.Fatalf("rows %d", n)
	}
}

func TestPutValidation(t *testing.T) {
	db, h := setup(t)
	owner, u := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	for _, b := range []string{`{}`, `{"rating":0}`, `{"rating":6}`, `{"rating":-1}`, `{"rating":3.5}`} {
		w, _ := put(t, h, u, s, b)
		if w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_rating") {
			t.Fatalf("%s: %d %s", b, w.Code, w.Body)
		}
	}
	long := strings.Repeat("ä", 1001)
	if w, _ := put(t, h, u, s, fmt.Sprintf(`{"rating":3,"body":%q}`, long)); w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_body") {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	ok := strings.Repeat("ä", 1000)
	if w, _ := put(t, h, u, s, fmt.Sprintf(`{"rating":3,"body":%q}`, ok)); w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if w, _ := put(t, h, u, s, `not json`); w.Code != 400 {
		t.Fatalf("%d", w.Code)
	}
}

func TestPutAuthOwnSpotAndMissing(t *testing.T) {
	db, h := setup(t)
	owner, u := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	if w, _ := put(t, h, 0, s, `{"rating":3}`); w.Code != 401 {
		t.Fatalf("%d", w.Code)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/spots/%d/review", s), 0, ""); w.Code != 401 {
		t.Fatalf("%d", w.Code)
	}
	if w, _ := put(t, h, owner, s, `{"rating":3}`); w.Code != 403 || !strings.Contains(w.Body.String(), "own_spot") {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if w, _ := put(t, h, u, 99999, `{"rating":3}`); w.Code != 404 || !strings.Contains(w.Body.String(), "not_found") {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	db.Exec(`UPDATE spots SET status='hidden' WHERE id=?`, s)
	if w, _ := put(t, h, u, s, `{"rating":3}`); w.Code != 404 {
		t.Fatalf("hidden: %d", w.Code)
	}
	if c, _ := list(t, h, 0, s, ""); c != 404 {
		t.Fatalf("hidden list: %d", c)
	}
	if c, _ := list(t, h, 0, 424242, ""); c != 404 {
		t.Fatalf("unknown list: %d", c)
	}
}

func TestDelete(t *testing.T) {
	db, h := setup(t)
	owner, u, v := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	if w := do(t, h, "DELETE", fmt.Sprintf("/spots/%d/review", s), u, ""); w.Code != 404 {
		t.Fatalf("none: %d", w.Code)
	}
	put(t, h, u, s, `{"rating":5}`)
	put(t, h, v, s, `{"rating":1}`)
	if w := do(t, h, "DELETE", fmt.Sprintf("/spots/%d/review", s), u, ""); w.Code != 204 {
		t.Fatalf("%d", w.Code)
	}
	_, l := list(t, h, 0, s, "")
	if l.Summary.Count != 1 || len(l.Items) != 1 || l.Items[0].Author.ID != v {
		t.Fatalf("%+v", l)
	}
	if w := do(t, h, "DELETE", fmt.Sprintf("/spots/%d/review", s), u, ""); w.Code != 404 {
		t.Fatalf("again: %d", w.Code)
	}
}

func TestSummaryMineAndAnonymous(t *testing.T) {
	db, h := setup(t)
	owner := testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	_, l := list(t, h, 0, s, "")
	if l.Summary.Count != 0 || l.Summary.Avg != 0 || l.Mine != nil || l.Items == nil || len(l.Items) != 0 || l.NextCursor != nil || len(l.Summary.Distribution) != 5 {
		t.Fatalf("empty: %+v", l)
	}
	users := make([]uint64, 5)
	for i := range users {
		users[i] = testutil.NewUser(t, db)
	}
	for i, r := range []int{5, 4, 4, 2, 1} {
		put(t, h, users[i], s, fmt.Sprintf(`{"rating":%d}`, r))
	}
	_, l = list(t, h, 0, s, "")
	d := l.Summary.Distribution
	if l.Summary.Count != 5 || l.Summary.Avg != 3.2 || d["1"] != 1 || d["2"] != 1 || d["3"] != 0 || d["4"] != 2 || d["5"] != 1 || l.Mine != nil {
		t.Fatalf("%+v", l)
	}
	put(t, h, users[0], s, `{"rating":3,"body":"meh"}`) // (3+4+4+2+1)/5 = 2.8
	_, l = list(t, h, users[0], s, "")
	if l.Summary.Avg != 2.8 || l.Summary.Distribution["5"] != 0 || l.Summary.Distribution["3"] != 1 {
		t.Fatalf("%+v", l)
	}
	if l.Mine == nil || l.Mine.Author.ID != users[0] || l.Mine.Rating != 3 || l.Mine.Body != "meh" {
		t.Fatalf("mine %+v", l.Mine)
	}
	_, l = list(t, h, users[1], s, "")
	if l.Mine == nil || l.Mine.Author.ID != users[1] {
		t.Fatalf("mine %+v", l.Mine)
	}
	if _, l = list(t, h, owner, s, ""); l.Mine != nil {
		t.Fatal("owner has no review")
	}
	// round half up: 20 reviews, sum 41 -> 2.05 -> 2.1
	db.Exec(`DELETE FROM spot_reviews WHERE spot_id=?`, s)
	for i := 0; i < 20; i++ {
		r := 2
		if i == 0 {
			r = 3
		}
		put(t, h, testutil.NewUser(t, db), s, fmt.Sprintf(`{"rating":%d}`, r))
	}
	_, l = list(t, h, 0, s, "")
	if l.Summary.Count != 20 || l.Summary.Avg != 2.1 {
		t.Fatalf("%+v", l.Summary)
	}
}

func TestPagination(t *testing.T) {
	db, h := setup(t)
	owner := testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	for i := 0; i < 5; i++ {
		put(t, h, testutil.NewUser(t, db), s, `{"rating":3}`)
	}
	db.Exec(`UPDATE spot_reviews SET created_at='2026-01-01 10:00:00'`) // identical timestamps
	var seen []uint64
	cur := ""
	for page := 0; page < 5; page++ {
		q := "?limit=2"
		if cur != "" {
			q += "&cursor=" + cur
		}
		code, l := list(t, h, 0, s, q)
		if code != 200 {
			t.Fatalf("%d", code)
		}
		for _, it := range l.Items {
			seen = append(seen, it.ID)
		}
		if l.NextCursor == nil {
			break
		}
		cur = *l.NextCursor
	}
	if len(seen) != 5 {
		t.Fatalf("seen %v", seen)
	}
	for i := 1; i < len(seen); i++ {
		if seen[i] >= seen[i-1] {
			t.Fatalf("not id desc: %v", seen)
		}
	}
	for _, q := range []string{"?limit=0", "?limit=x", "?limit=-3"} {
		w := do(t, h, "GET", fmt.Sprintf("/spots/%d/reviews%s", s, q), 0, "")
		if w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_limit") {
			t.Fatalf("%s %d %s", q, w.Code, w.Body)
		}
	}
	if w := do(t, h, "GET", fmt.Sprintf("/spots/%d/reviews?cursor=%%25%%25", s), 0, ""); w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_cursor") {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if _, l := list(t, h, 0, s, "?limit=500"); len(l.Items) != 5 {
		t.Fatal("limit clamp")
	}
}

func TestReportHidesReview(t *testing.T) {
	db, h := setup(t)
	owner, author := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	_, rv := put(t, h, author, s, `{"rating":1,"body":"spam"}`)
	put(t, h, testutil.NewUser(t, db), s, `{"rating":5}`)
	rep := func(u uint64, id uint64) int {
		return do(t, h, "POST", "/reports", u, fmt.Sprintf(`{"target_type":"review","target_id":%d,"reason":"x"}`, id)).Code
	}
	if c := rep(testutil.NewUser(t, db), 999999); c != 404 {
		t.Fatalf("missing %d", c)
	}
	r1, r2, r3 := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	if c := rep(r1, rv.ID); c != 201 {
		t.Fatalf("%d", c)
	}
	if c := rep(r1, rv.ID); c != 200 {
		t.Fatalf("dup %d", c)
	}
	rep(r2, rv.ID)
	if _, l := list(t, h, 0, s, ""); l.Summary.Count != 2 {
		t.Fatalf("hidden too early %+v", l.Summary)
	}
	rep(r3, rv.ID)
	_, l := list(t, h, author, s, "")
	if l.Summary.Count != 1 || l.Summary.Avg != 5 || len(l.Items) != 1 || l.Mine != nil || l.Summary.Distribution["1"] != 0 {
		t.Fatalf("%+v", l)
	}
	if c := rep(testutil.NewUser(t, db), rv.ID); c != 404 {
		t.Fatalf("hidden target should 404, got %d", c)
	}
}

func TestSpotAndUserDeleteCascadeReviews(t *testing.T) {
	db, h := setup(t)
	owner, u := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	put(t, h, u, s, `{"rating":4}`)
	db.Exec(`DELETE FROM spots WHERE id=?`, s)
	var n int
	db.QueryRow(`SELECT COUNT(*) FROM spot_reviews`).Scan(&n)
	if n != 0 {
		t.Fatal("reviews remain")
	}
	s2 := newSpot(t, db, owner)
	put(t, h, u, s2, `{"rating":4}`)
	db.Exec(`DELETE FROM users WHERE id=?`, u)
	db.QueryRow(`SELECT COUNT(*) FROM spot_reviews`).Scan(&n)
	if n != 0 {
		t.Fatal("reviews remain after user delete")
	}
}
