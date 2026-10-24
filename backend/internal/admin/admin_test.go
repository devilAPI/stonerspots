package admin_test

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/admin"
	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/engagement"
	"stonerspots/backend/internal/spots"
	"stonerspots/backend/internal/testutil"
)

type env struct {
	db     *sql.DB
	h      http.Handler
	upload string
	admin  uint64
	tok    string
}

func setup(t *testing.T) *env {
	t.Helper()
	db := testutil.NewDB(t)
	up := t.TempDir()
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) {
		deps := app.Deps{DB: db, Cfg: config.Config{
			JWTSecret: []byte(testutil.JWTSecret), UploadDir: up, PublicBaseURL: "http://test"}}
		admin.Mount(r, deps)
		engagement.Mount(r, deps)
		spots.Mount(r, deps)
	})
	a := testutil.NewUser(t, db)
	if _, err := db.Exec(`UPDATE users SET is_admin=1 WHERE id=?`, a); err != nil {
		t.Fatal(err)
	}
	return &env{db: db, h: r, upload: up, admin: a, tok: testutil.Token(t, a)}
}

func (e *env) do(t *testing.T, method, path, tok string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/api/v1"+path, nil)
	if tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, req)
	return w
}

func exec(t *testing.T, db *sql.DB, q string, args ...any) int64 {
	t.Helper()
	res, err := db.Exec(q, args...)
	if err != nil {
		t.Fatalf("%s: %v", q, err)
	}
	id, _ := res.LastInsertId()
	return id
}

func newSpot(t *testing.T, db *sql.DB, owner uint64, title, status string) uint64 {
	return uint64(exec(t, db, `INSERT INTO spots (user_id, title, description, category, location, status)
		VALUES (?, ?, 'd', 'bench', ST_GeomFromText('POINT(10 50)'), ?)`, owner, title, status))
}

func newUpdate(t *testing.T, db *sql.DB, spot, owner uint64, body string) uint64 {
	return uint64(exec(t, db, `INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, ?)`, spot, owner, body))
}

func report(t *testing.T, db *sql.DB, reporter uint64, typ string, target uint64, reason string) uint64 {
	return uint64(exec(t, db, `INSERT INTO reports (user_id, target_type, target_id, reason, created_at)
		VALUES (?, ?, ?, ?, '2026-01-01 00:00:00')`, reporter, typ, target, reason))
}

func decode(t *testing.T, w *httptest.ResponseRecorder, v any) {
	t.Helper()
	if err := json.Unmarshal(w.Body.Bytes(), v); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
}

func errCode(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var b struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	decode(t, w, &b)
	return b.Error.Code
}

func TestAccessControl(t *testing.T) {
	e := setup(t)
	user := testutil.NewUser(t, e.db)
	utok := testutil.Token(t, user)
	routes := [][2]string{
		{"GET", "/admin/reports"}, {"GET", "/admin/users"}, {"GET", "/admin/spots"}, {"DELETE", "/admin/spots/1"},
	}
	for _, rt := range routes {
		if c := e.do(t, rt[0], rt[1], "").Code; c != 401 {
			t.Errorf("%v anon = %d", rt, c)
		}
		w := e.do(t, rt[0], rt[1], utok)
		if w.Code != 403 || errCode(t, w) != "forbidden" {
			t.Errorf("%v user = %d %s", rt, w.Code, w.Body)
		}
	}
	if c := e.do(t, "GET", "/admin/users", e.tok).Code; c != 200 {
		t.Fatalf("admin = %d", c)
	}
	exec(t, e.db, `UPDATE users SET is_admin=0 WHERE id=?`, e.admin)
	if c := e.do(t, "GET", "/admin/users", e.tok).Code; c != 403 {
		t.Fatalf("revoked admin = %d", c)
	}
}

type userRef struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
	Email       string `json:"email"`
}

type reportItem struct {
	ID          uint64  `json:"id"`
	TargetType  string  `json:"target_type"`
	TargetID    uint64  `json:"target_id"`
	Reason      string  `json:"reason"`
	CreatedAt   string  `json:"created_at"`
	ReportCount int     `json:"report_count"`
	Reporter    userRef `json:"reporter"`
	Target      struct {
		Exists bool    `json:"exists"`
		SpotID uint64  `json:"spot_id"`
		Title  string  `json:"title"`
		Status string  `json:"status"`
		Body   string  `json:"body"`
		Author userRef `json:"author"`
	} `json:"target"`
}

type reportsPage struct {
	Items      []reportItem `json:"items"`
	NextCursor *string      `json:"next_cursor"`
}

func TestReports(t *testing.T) {
	e := setup(t)
	author := testutil.NewUser(t, e.db)
	r1, r2 := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	spot := newSpot(t, e.db, author, "Bench", "hidden")
	upd := newUpdate(t, e.db, spot, author, "update text")
	gone := newSpot(t, e.db, author, "Gone", "active")

	a := report(t, e.db, r1, "spot", spot, "spam")
	b := report(t, e.db, r2, "spot", spot, "bad")
	c := report(t, e.db, r1, "update", upd, "rude")
	d := report(t, e.db, r1, "spot", gone, "x")
	exec(t, e.db, `DELETE FROM spots WHERE id=?`, gone)

	w := e.do(t, "GET", "/admin/reports", e.tok)
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	var p reportsPage
	decode(t, w, &p)
	if len(p.Items) != 4 || p.NextCursor != nil {
		t.Fatalf("items %d cursor %v", len(p.Items), p.NextCursor)
	}
	if p.Items[0].ID != d || p.Items[1].ID != c || p.Items[2].ID != b || p.Items[3].ID != a {
		t.Fatalf("order wrong: %+v", p.Items)
	}
	if x := p.Items[0]; x.Target.Exists || x.Target.Title != "" || x.TargetType != "spot" {
		t.Errorf("deleted target: %+v", x)
	}
	u := p.Items[1]
	if !u.Target.Exists || u.TargetType != "update" || u.Target.SpotID != spot || u.Target.Title != "Bench" ||
		u.Target.Body != "update text" || u.Target.Author.ID != author || u.Target.Status != "hidden" ||
		u.ReportCount != 1 || u.Reporter.ID != r1 || u.Reporter.Email == "" || u.Reason != "rude" || u.CreatedAt != "2026-01-01T00:00:00Z" {
		t.Errorf("update report: %+v", u)
	}
	s := p.Items[3]
	if !s.Target.Exists || s.Target.SpotID != spot || s.Target.Body != "" || s.ReportCount != 2 || s.Target.Author.DisplayName == "" {
		t.Errorf("spot report: %+v", s)
	}

	// pagination (identical timestamps)
	var ids []uint64
	cur := ""
	for i := 0; i < 5; i++ {
		path := "/admin/reports?limit=3"
		if cur != "" {
			path += "&cursor=" + cur
		}
		var pg reportsPage
		decode(t, e.do(t, "GET", path, e.tok), &pg)
		for _, it := range pg.Items {
			ids = append(ids, it.ID)
		}
		if pg.NextCursor == nil {
			break
		}
		cur = *pg.NextCursor
	}
	if fmt.Sprint(ids) != fmt.Sprint([]uint64{d, c, b, a}) {
		t.Fatalf("paged ids %v", ids)
	}

	for path, code := range map[string]string{
		"/admin/reports?limit=0": "invalid_limit", "/admin/reports?limit=101": "invalid_limit",
		"/admin/reports?limit=x": "invalid_limit", "/admin/reports?cursor=!!": "invalid_cursor",
	} {
		w := e.do(t, "GET", path, e.tok)
		if w.Code != 400 || errCode(t, w) != code {
			t.Errorf("%s: %d %s", path, w.Code, w.Body)
		}
	}
}

func TestReportsEmpty(t *testing.T) {
	e := setup(t)
	w := e.do(t, "GET", "/admin/reports", e.tok)
	if w.Body.String() != "{\"items\":[],\"next_cursor\":null}\n" {
		t.Fatalf("%q", w.Body.String())
	}
}

func TestUsers(t *testing.T) {
	e := setup(t)
	alice := testutil.NewUser(t, e.db)
	bob := testutil.NewUser(t, e.db)
	exec(t, e.db, `UPDATE users SET display_name='100%_Alice', email='alice@x.test' WHERE id=?`, alice)
	exec(t, e.db, `UPDATE users SET display_name='Bobby', email='bob@x.test' WHERE id=?`, bob)
	s := newSpot(t, e.db, alice, "S", "active")
	u := newUpdate(t, e.db, s, alice, "b")
	report(t, e.db, bob, "spot", s, "")
	report(t, e.db, bob, "update", u, "")
	report(t, e.db, e.admin, "spot", s, "")

	type item struct {
		ID              uint64 `json:"id"`
		Email           string `json:"email"`
		IsAdmin         bool   `json:"is_admin"`
		CreatedAt       string `json:"created_at"`
		SpotCount       int    `json:"spot_count"`
		ReportsReceived int    `json:"reports_received"`
	}
	type page struct {
		Items      []item  `json:"items"`
		NextCursor *string `json:"next_cursor"`
	}
	var p page
	decode(t, e.do(t, "GET", "/admin/users", e.tok), &p)
	if len(p.Items) != 3 || p.Items[0].ID != bob || p.Items[1].ID != alice || p.Items[2].ID != e.admin || !p.Items[2].IsAdmin {
		t.Fatalf("%+v", p.Items)
	}
	if p.Items[1].SpotCount != 1 || p.Items[1].ReportsReceived != 3 || p.Items[0].ReportsReceived != 0 || p.Items[1].CreatedAt == "" {
		t.Fatalf("counts %+v", p.Items)
	}

	// pagination
	decode(t, e.do(t, "GET", "/admin/users?limit=2", e.tok), &p)
	if len(p.Items) != 2 || p.NextCursor == nil {
		t.Fatalf("page1 %+v", p)
	}
	var p2 page
	decode(t, e.do(t, "GET", "/admin/users?limit=2&cursor="+*p.NextCursor, e.tok), &p2)
	if len(p2.Items) != 1 || p2.Items[0].ID != e.admin || p2.NextCursor != nil {
		t.Fatalf("page2 %+v", p2)
	}

	// q: name, email, wildcard escaping
	for q, want := range map[string][]uint64{
		"bobby": {bob}, "alice@x": {alice}, "%25": {alice}, "_": {alice}, "100%25_": {alice}, "zzz": nil, "x.test": {bob, alice},
	} {
		var pq page
		decode(t, e.do(t, "GET", "/admin/users?q="+q, e.tok), &pq)
		var got []uint64
		for _, it := range pq.Items {
			got = append(got, it.ID)
		}
		if fmt.Sprint(got) != fmt.Sprint(want) {
			t.Errorf("q=%q got %v want %v", q, got, want)
		}
	}
}

func TestSpots(t *testing.T) {
	e := setup(t)
	au := testutil.NewUser(t, e.db)
	rep := testutil.NewUser(t, e.db)
	s1 := newSpot(t, e.db, au, "Quiet bench", "active")
	s2 := newSpot(t, e.db, au, "Hidden 100% spot", "hidden")
	s3 := newSpot(t, e.db, au, "Lake", "active")
	report(t, e.db, rep, "spot", s2, "")

	type item struct {
		ID          uint64  `json:"id"`
		Title       string  `json:"title"`
		Category    string  `json:"category"`
		Lat         float64 `json:"lat"`
		Lon         float64 `json:"lon"`
		Status      string  `json:"status"`
		LikeCount   int     `json:"like_count"`
		CreatedAt   string  `json:"created_at"`
		ReportCount int     `json:"report_count"`
		Author      userRef `json:"author"`
	}
	type page struct {
		Items      []item  `json:"items"`
		NextCursor *string `json:"next_cursor"`
	}
	get := func(q string) (int, page, *httptest.ResponseRecorder) {
		w := e.do(t, "GET", "/admin/spots"+q, e.tok)
		var p page
		if w.Code == 200 {
			decode(t, w, &p)
		}
		return w.Code, p, w
	}
	_, p, _ := get("")
	if len(p.Items) != 3 || p.Items[0].ID != s3 || p.Items[1].ID != s2 || p.Items[2].ID != s1 {
		t.Fatalf("%+v", p.Items)
	}
	h := p.Items[1]
	if h.Status != "hidden" || h.ReportCount != 1 || h.Author.ID != au || h.Category != "bench" || h.Lat != 50 || h.Lon != 10 || h.CreatedAt == "" {
		t.Fatalf("hidden item %+v", h)
	}
	_, p, _ = get("?status=hidden")
	if len(p.Items) != 1 || p.Items[0].ID != s2 {
		t.Fatalf("hidden filter %+v", p.Items)
	}
	_, p, _ = get("?status=active")
	if len(p.Items) != 2 {
		t.Fatalf("active filter %+v", p.Items)
	}
	_, p, _ = get("?q=100%25")
	if len(p.Items) != 1 || p.Items[0].ID != s2 {
		t.Fatalf("q %+v", p.Items)
	}
	_, p, _ = get("?q=%25")
	if len(p.Items) != 1 {
		t.Fatalf("literal %% %+v", p.Items)
	}
	_, p, _ = get("?q=BENCH")
	if len(p.Items) != 1 || p.Items[0].ID != s1 {
		t.Fatalf("q bench %+v", p.Items)
	}
	_, p, _ = get("?limit=2")
	if len(p.Items) != 2 || p.NextCursor == nil {
		t.Fatalf("limit %+v", p)
	}
	_, p2, _ := get("?limit=2&cursor=" + *p.NextCursor)
	if len(p2.Items) != 1 || p2.Items[0].ID != s1 || p2.NextCursor != nil {
		t.Fatalf("page2 %+v", p2)
	}
	code, _, w := get("?status=bogus")
	if code != 400 || errCode(t, w) != "invalid_status" {
		t.Fatalf("status: %d %s", code, w.Body)
	}
	code, _, w = get("?cursor=abc")
	if code != 400 || errCode(t, w) != "invalid_cursor" {
		t.Fatalf("cursor: %d %s", code, w.Body)
	}
}

func count(t *testing.T, db *sql.DB, q string, args ...any) int {
	t.Helper()
	var n int
	if err := db.QueryRow(q, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestDeleteSpot(t *testing.T) {
	e := setup(t)
	au := testutil.NewUser(t, e.db)
	other := testutil.NewUser(t, e.db)
	s := newSpot(t, e.db, au, "Doomed", "active")
	keep := newSpot(t, e.db, au, "Keep", "active")
	u := newUpdate(t, e.db, s, au, "b")
	ku := newUpdate(t, e.db, keep, au, "kb")
	exec(t, e.db, `INSERT INTO spot_likes (user_id, spot_id) VALUES (?, ?)`, other, s)
	exec(t, e.db, `INSERT INTO spot_likes (user_id, spot_id) VALUES (?, ?)`, other, keep)
	write := func(name string) string {
		if err := os.WriteFile(filepath.Join(e.upload, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		return name
	}
	photo := func(owner, upd uint64, k, tk string) {
		exec(t, e.db, "INSERT INTO photos (user_id, `key`, thumb_key, width, height, update_id) VALUES (?, ?, ?, 1, 1, ?)", owner, k, tk, upd)
	}
	photo(au, u, write("a.jpg"), write("a_t.jpg"))
	photo(au, ku, write("k.jpg"), write("k_t.jpg"))
	// unsafe key must be skipped, never escaping the upload dir
	outside := filepath.Join(filepath.Dir(e.upload), "outside-"+filepath.Base(e.upload))
	if err := os.WriteFile(outside, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(outside)
	photo(au, u, "../"+filepath.Base(outside), "")
	report(t, e.db, other, "spot", s, "")
	report(t, e.db, other, "update", u, "")
	report(t, e.db, other, "spot", keep, "")
	report(t, e.db, other, "update", ku, "")

	w := e.do(t, "DELETE", fmt.Sprintf("/admin/spots/%d", s), e.tok)
	if w.Code != 204 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE id=?`, s); n != 0 {
		t.Fatal("spot remains")
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spot_updates WHERE spot_id=?`, s); n != 0 {
		t.Fatal("updates remain")
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spot_likes WHERE spot_id=?`, s); n != 0 {
		t.Fatal("likes remain")
	}
	if n := count(t, e.db, "SELECT COUNT(*) FROM photos WHERE `key` IN ('a.jpg') OR `key` LIKE '../%'"); n != 0 {
		t.Fatal("photo rows remain")
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM reports`); n != 2 {
		t.Fatalf("reports left = %d, want 2", n)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM reports WHERE (target_type='spot' AND target_id=?) OR (target_type='update' AND target_id=?)`, s, u); n != 0 {
		t.Fatal("reports about spot remain")
	}
	for _, f := range []string{"a.jpg", "a_t.jpg"} {
		if _, err := os.Stat(filepath.Join(e.upload, f)); !os.IsNotExist(err) {
			t.Errorf("%s still exists", f)
		}
	}
	for _, f := range []string{"k.jpg", "k_t.jpg"} {
		if _, err := os.Stat(filepath.Join(e.upload, f)); err != nil {
			t.Errorf("%s removed: %v", f, err)
		}
	}
	if _, err := os.Stat(outside); err != nil {
		t.Errorf("file outside upload dir was removed")
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE id=?`, keep); n != 1 {
		t.Fatal("other spot gone")
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spot_likes WHERE spot_id=?`, keep); n != 1 {
		t.Fatal("other likes gone")
	}

	w = e.do(t, "DELETE", fmt.Sprintf("/admin/spots/%d", s), e.tok)
	if w.Code != 404 || errCode(t, w) != "not_found" {
		t.Fatalf("second delete: %d %s", w.Code, w.Body)
	}
	w = e.do(t, "DELETE", "/admin/spots/abc", e.tok)
	if w.Code != 404 {
		t.Fatalf("bad id: %d", w.Code)
	}
}
