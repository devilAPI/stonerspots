package engagement_test

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/engagement"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/testutil"
)

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	engagement.Mount(r, app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}}, quotas.NewTracker(quotas.Config{}))
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

type likeResp struct {
	Liked     bool `json:"liked"`
	LikeCount int  `json:"like_count"`
}

func like(t *testing.T, h http.Handler, method string, user, spot uint64) (int, likeResp) {
	t.Helper()
	w := do(t, h, method, fmt.Sprintf("/spots/%d/like", spot), user, "")
	var lr likeResp
	_ = json.Unmarshal(w.Body.Bytes(), &lr)
	return w.Code, lr
}

func counts(t *testing.T, db *sql.DB, spot uint64) (int, int) {
	t.Helper()
	var c, n int
	if err := db.QueryRow(`SELECT like_count FROM spots WHERE id=?`, spot).Scan(&c); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM spot_likes WHERE spot_id=?`, spot).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return c, n
}

func TestLikeIsIdempotent(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u)
	for i := 0; i < 2; i++ {
		code, lr := like(t, h, "PUT", u, s)
		if code != 200 || !lr.Liked || lr.LikeCount != 1 {
			t.Fatalf("got %d %+v", code, lr)
		}
	}
	if c, n := counts(t, db, s); c != 1 || n != 1 {
		t.Fatalf("count=%d rows=%d", c, n)
	}
	if code, _ := like(t, h, "PUT", 0, s); code != 401 {
		t.Fatalf("unauth got %d", code)
	}
	w := do(t, h, "PUT", "/spots/9999/like", u, "")
	if w.Code != 404 || !strings.Contains(w.Body.String(), "not_found") {
		t.Fatalf("got %d %s", w.Code, w.Body)
	}
}

func TestUnlikeNeverGoesNegative(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u)
	for i := 0; i < 2; i++ {
		code, lr := like(t, h, "DELETE", u, s)
		if code != 200 || lr.Liked || lr.LikeCount != 0 {
			t.Fatalf("got %d %+v", code, lr)
		}
	}
	like(t, h, "PUT", u, s)
	_, lr := like(t, h, "DELETE", u, s)
	if lr.LikeCount != 0 || lr.Liked {
		t.Fatalf("%+v", lr)
	}
	if c, n := counts(t, db, s); c != 0 || n != 0 {
		t.Fatalf("count=%d rows=%d", c, n)
	}
}

func TestConcurrentLikesKeepCountConsistent(t *testing.T) {
	db, h := setup(t)
	owner := testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	users := make([]uint64, 20)
	for i := range users {
		users[i] = testutil.NewUser(t, db)
	}
	var wg sync.WaitGroup
	for _, u := range users {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 2; j++ { // twice per user to also race duplicates
				if code, _ := like(t, h, "PUT", u, s); code != 200 {
					t.Errorf("code %d", code)
				}
			}
		}()
	}
	wg.Wait()
	if c, n := counts(t, db, s); c != 20 || n != 20 {
		t.Fatalf("count=%d rows=%d", c, n)
	}
}

func report(t *testing.T, h http.Handler, user uint64, typ string, id uint64) *httptest.ResponseRecorder {
	t.Helper()
	return do(t, h, "POST", "/reports", user, fmt.Sprintf(`{"target_type":%q,"target_id":%d,"reason":"spam"}`, typ, id))
}

func status(t *testing.T, db *sql.DB, table string, id uint64) string {
	t.Helper()
	var s string
	if err := db.QueryRow("SELECT status FROM "+table+" WHERE id=?", id).Scan(&s); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestThreeReportsHideTarget(t *testing.T) {
	db, h := setup(t)
	owner := testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	up := newUpdate(t, db, s, owner)
	for i := 0; i < 3; i++ {
		if status(t, db, "spots", s) != "active" || status(t, db, "spot_updates", up) != "active" {
			t.Fatalf("hidden too early at %d", i)
		}
		u := testutil.NewUser(t, db)
		if w := report(t, h, u, "spot", s); w.Code != 201 {
			t.Fatalf("spot report %d %s", w.Code, w.Body)
		}
		if w := report(t, h, u, "update", up); w.Code != 201 {
			t.Fatalf("update report %d %s", w.Code, w.Body)
		}
	}
	if status(t, db, "spots", s) != "hidden" || status(t, db, "spot_updates", up) != "hidden" {
		t.Fatal("not hidden")
	}
	u := testutil.NewUser(t, db)
	if w := report(t, h, u, "spot", 9999); w.Code != 404 {
		t.Fatalf("got %d", w.Code)
	}
	if w := report(t, h, u, "photo", s); w.Code != 400 || !strings.Contains(w.Body.String(), "invalid_target") {
		t.Fatalf("got %d %s", w.Code, w.Body)
	}
	if w := report(t, h, 0, "spot", s); w.Code != 401 {
		t.Fatalf("got %d", w.Code)
	}
}

func TestSameUserReportingTwiceCountsOnce(t *testing.T) {
	db, h := setup(t)
	owner := testutil.NewUser(t, db)
	s := newSpot(t, db, owner)
	u := testutil.NewUser(t, db)
	if w := report(t, h, u, "spot", s); w.Code != 201 {
		t.Fatalf("got %d", w.Code)
	}
	for i := 0; i < 3; i++ {
		if w := report(t, h, u, "spot", s); w.Code != 200 {
			t.Fatalf("got %d", w.Code)
		}
	}
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM reports WHERE target_id=?`, s).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 1 || status(t, db, "spots", s) != "active" {
		t.Fatalf("n=%d status=%s", n, status(t, db, "spots", s))
	}
}
