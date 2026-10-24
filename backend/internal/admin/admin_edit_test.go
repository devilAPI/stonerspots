package admin_test

import (
	"database/sql"
	"fmt"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func (e *env) send(t *testing.T, method, path, tok, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/api/v1"+path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, req)
	return w
}

func (e *env) expect(t *testing.T, w *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if w.Code != status {
		t.Fatalf("status = %d, want %d: %s", w.Code, status, w.Body)
	}
	if code != "" {
		if got := errCode(t, w); got != code {
			t.Fatalf("code = %q, want %q: %s", got, code, w.Body)
		}
	}
}

func (e *env) emailOf(t *testing.T, id uint64) string {
	t.Helper()
	var s string
	if err := e.db.QueryRow(`SELECT email FROM users WHERE id=?`, id).Scan(&s); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestEditAccessControl(t *testing.T) {
	e := setup(t)
	utok := testutil.Token(t, testutil.NewUser(t, e.db))
	routes := [][3]string{
		{"PATCH", "/admin/users/1", `{"display_name":"x"}`},
		{"PATCH", "/admin/spots/1", `{"title":"abc"}`},
		{"DELETE", "/admin/reports/1", ""},
		{"POST", "/admin/reports/dismiss", `{"target_type":"spot","target_id":1}`},
	}
	for _, rt := range routes {
		if c := e.send(t, rt[0], rt[1], "", rt[2]).Code; c != 401 {
			t.Errorf("%v anon = %d", rt, c)
		}
		e.expect(t, e.send(t, rt[0], rt[1], utok, rt[2]), 403, "forbidden")
	}
}

type userOut struct {
	ID              uint64 `json:"id"`
	Email           string `json:"email"`
	DisplayName     string `json:"display_name"`
	IsAdmin         bool   `json:"is_admin"`
	CreatedAt       string `json:"created_at"`
	SpotCount       int    `json:"spot_count"`
	ReportsReceived int    `json:"reports_received"`
}

func (e *env) patchUser(t *testing.T, id uint64, body string) *httptest.ResponseRecorder {
	return e.send(t, "PATCH", fmt.Sprintf("/admin/users/%d", id), e.tok, body)
}

func TestPatchUserValidation(t *testing.T) {
	e := setup(t)
	other := testutil.NewUser(t, e.db)
	cases := []struct {
		name, body string
		status     int
		code       string
	}{
		{"empty", `{}`, 400, "empty_patch"},
		{"unknown only", `{"foo":1}`, 400, "empty_patch"},
		{"null name", `{"display_name":null}`, 400, "invalid_body"},
		{"null email", `{"email":null}`, 400, "invalid_body"},
		{"null admin", `{"is_admin":null}`, 400, "invalid_body"},
		{"not json", `nope`, 400, "invalid_body"},
		{"name blank", `{"display_name":"   "}`, 400, "invalid_display_name"},
		{"name 81", `{"display_name":"` + strings.Repeat("ä", 81) + `"}`, 400, "invalid_display_name"},
		{"name 80", `{"display_name":"` + strings.Repeat("ä", 80) + `"}`, 200, ""},
		{"name 1", `{"display_name":" a "}`, 200, ""},
		{"bad email", `{"email":"nope"}`, 400, "invalid_email"},
		{"email wrong type", `{"email":5}`, 400, "invalid_body"},
		{"admin wrong type", `{"is_admin":"yes"}`, 400, "invalid_body"},
		{"taken email", `{"email":" ` + strings.ToUpper(e.emailOf(t, e.admin)) + ` "}`, 409, "email_taken"},
	}
	for _, c := range cases {
		w := e.patchUser(t, other, c.body)
		if w.Code != c.status || (c.code != "" && errCode(t, w) != c.code) {
			t.Errorf("%s: %d %s", c.name, w.Code, w.Body)
		}
	}
	e.expect(t, e.patchUser(t, 999999, `{"display_name":"x"}`), 404, "not_found")
	e.expect(t, e.send(t, "PATCH", "/admin/users/abc", e.tok, `{"display_name":"x"}`), 404, "not_found")
}

func TestPatchUserEmailAndFields(t *testing.T) {
	e := setup(t)
	u := testutil.NewUser(t, e.db)
	newSpot(t, e.db, u, "one", "active")
	const snap = `SELECT CONCAT(password_hash,'|',is_admin,'|',display_name) FROM users WHERE id=?`
	var before string
	_ = e.db.QueryRow(snap, u).Scan(&before)

	w := e.patchUser(t, u, `{"email":"  New.Person@Example.TEST "}`)
	e.expect(t, w, 200, "")
	var got userOut
	decode(t, w, &got)
	if got.Email != "new.person@example.test" || got.ID != u || got.SpotCount != 1 || got.CreatedAt == "" {
		t.Fatalf("got %+v", got)
	}
	var after string
	_ = e.db.QueryRow(snap, u).Scan(&after)
	if before != after {
		t.Fatalf("other fields changed: %q -> %q", before, after)
	}
	// own current email (different case) is fine
	e.expect(t, e.patchUser(t, u, `{"email":"NEW.person@example.test"}`), 200, "")
	// only display_name changes; unknown keys ignored
	w = e.patchUser(t, u, `{"display_name":"  Neo  ","bogus":true}`)
	e.expect(t, w, 200, "")
	decode(t, w, &got)
	if got.DisplayName != "Neo" || got.Email != "new.person@example.test" || got.IsAdmin {
		t.Fatalf("got %+v", got)
	}
	// promote
	w = e.patchUser(t, u, `{"is_admin":true}`)
	e.expect(t, w, 200, "")
	decode(t, w, &got)
	if !got.IsAdmin || got.DisplayName != "Neo" {
		t.Fatalf("got %+v", got)
	}
}

func TestPatchUserAdminGuards(t *testing.T) {
	e := setup(t)
	e.expect(t, e.patchUser(t, e.admin, `{"is_admin":false}`), 400, "cannot_demote_self")
	e.expect(t, e.patchUser(t, e.admin, `{"is_admin":true}`), 200, "")
	b := testutil.NewUser(t, e.db)
	e.expect(t, e.patchUser(t, b, `{"is_admin":true}`), 200, "")
	btok := testutil.Token(t, b)
	// self-demotion is refused even with two admins
	e.expect(t, e.send(t, "PATCH", fmt.Sprintf("/admin/users/%d", b), btok, `{"is_admin":false}`), 400, "cannot_demote_self")
	// promote another, then demote works
	e.expect(t, e.patchUser(t, b, `{"is_admin":false}`), 200, "")
	var n int
	_ = e.db.QueryRow(`SELECT COUNT(*) FROM users WHERE is_admin=1`).Scan(&n)
	if n != 1 {
		t.Fatalf("admins = %d", n)
	}
	// demoting an already non-admin is a no-op success
	e.expect(t, e.patchUser(t, b, `{"is_admin":false}`), 200, "")
}

func TestPatchUserConcurrentDemotion(t *testing.T) {
	for round := 0; round < 5; round++ {
		e := setup(t)
		b := testutil.NewUser(t, e.db)
		exec(t, e.db, `UPDATE users SET is_admin=1 WHERE id=?`, b)
		btok := testutil.Token(t, b)
		var wg sync.WaitGroup
		codes := make([]int, 2)
		start := make(chan struct{})
		for i, c := range []struct {
			tok    string
			target uint64
		}{{e.tok, b}, {btok, e.admin}} {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				codes[i] = e.send(t, "PATCH", fmt.Sprintf("/admin/users/%d", c.target), c.tok, `{"is_admin":false}`).Code
			}()
		}
		close(start)
		wg.Wait()
		var n int
		_ = e.db.QueryRow(`SELECT COUNT(*) FROM users WHERE is_admin=1`).Scan(&n)
		if n < 1 {
			t.Fatalf("round %d: no admin left, codes %v", round, codes)
		}
	}
}

// ---- spots ----

type spotOut struct {
	ID          uint64  `json:"id"`
	Title       string  `json:"title"`
	Description string  `json:"description"`
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
	Status      string  `json:"status"`
	LikeCount   int     `json:"like_count"`
	CreatedAt   string  `json:"created_at"`
	Author      struct {
		ID          uint64 `json:"id"`
		DisplayName string `json:"display_name"`
	} `json:"author"`
	ReportCount int `json:"report_count"`
}

func (e *env) patchSpot(t *testing.T, id uint64, body string) *httptest.ResponseRecorder {
	return e.send(t, "PATCH", fmt.Sprintf("/admin/spots/%d", id), e.tok, body)
}

func TestPatchSpotValidation(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	id := newSpot(t, e.db, owner, "Original", "active")
	cases := []struct {
		name, body string
		status     int
		code       string
	}{
		{"empty", `{}`, 400, "empty_patch"},
		{"unknown", `{"x":1}`, 400, "empty_patch"},
		{"null", `{"title":null}`, 400, "invalid_body"},
		{"null lat", `{"lat":null,"lon":10}`, 400, "invalid_body"},
		{"bad json", `[`, 400, "invalid_body"},
		{"title 2", `{"title":"ab"}`, 400, "invalid_title"},
		{"title 2 padded", `{"title":"  ab  "}`, 400, "invalid_title"},
		{"title 3", `{"title":"abc"}`, 200, ""},
		{"title 80", `{"title":"` + strings.Repeat("ü", 80) + `"}`, 200, ""},
		{"title 81", `{"title":"` + strings.Repeat("ü", 81) + `"}`, 400, "invalid_title"},
		{"desc 1000", `{"description":"` + strings.Repeat("ü", 1000) + `"}`, 200, ""},
		{"desc 1001", `{"description":"` + strings.Repeat("ü", 1001) + `"}`, 400, "invalid_description"},
		{"desc empty", `{"description":""}`, 200, ""},
		{"category alone is ignored", `{"category":"mars"}`, 400, "empty_patch"},
		{"category plus title", `{"title":"abc","category":"mars"}`, 200, ""},
		{"status", `{"status":"deleted"}`, 400, "invalid_status"},
		{"lat only", `{"lat":50}`, 400, "invalid_location"},
		{"lon only", `{"lon":10}`, 400, "invalid_location"},
		{"out of range", `{"lat":95,"lon":10}`, 400, "invalid_location"},
		{"outside box", `{"lat":40,"lon":10}`, 400, "invalid_location"},
		{"swapped", `{"lat":10,"lon":50}`, 400, "invalid_location"},
		{"title type", `{"title":5}`, 400, "invalid_body"},
		{"lat type", `{"lat":"a","lon":10}`, 400, "invalid_body"},
	}
	for _, c := range cases {
		w := e.patchSpot(t, id, c.body)
		if w.Code != c.status || (c.code != "" && errCode(t, w) != c.code) {
			t.Errorf("%s: %d %s", c.name, w.Code, w.Body)
		}
	}
	e.expect(t, e.patchSpot(t, 999999, `{"title":"abc"}`), 404, "not_found")
	e.expect(t, e.send(t, "PATCH", "/admin/spots/zz", e.tok, `{"title":"abc"}`), 404, "not_found")
}

func TestPatchSpotChangesOnlyGivenAndMoves(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	id := newSpot(t, e.db, owner, "Original", "active")
	w := e.patchSpot(t, id, `{"description":"new desc"}`)
	e.expect(t, w, 200, "")
	var s spotOut
	decode(t, w, &s)
	if s.Title != "Original" || s.Description != "new desc" || s.Lat != 50 || s.Lon != 10 ||
		s.Status != "active" || s.Author.ID != owner || s.Author.DisplayName == "" || s.CreatedAt == "" {
		t.Fatalf("got %+v", s)
	}
	if strings.Contains(w.Body.String(), "category") {
		t.Fatalf("admin spot must not contain category: %s", w.Body)
	}
	var pub struct {
		Description string `json:"description"`
	}
	pw := e.do(t, "GET", fmt.Sprintf("/spots/%d", id), "")
	decode(t, pw, &pub)
	if pw.Code != 200 || pub.Description != "new desc" {
		t.Fatalf("public: %d %s", pw.Code, pw.Body)
	}

	w = e.patchSpot(t, id, `{"title":"  Moved  ","lat":48.1,"lon":11.5}`)
	e.expect(t, w, 200, "")
	decode(t, w, &s)
	if s.Title != "Moved" || s.Lat != 48.1 || s.Lon != 11.5 || s.Description != "new desc" {
		t.Fatalf("got %+v", s)
	}
	var x, y float64
	if err := e.db.QueryRow(`SELECT ST_X(location), ST_Y(location) FROM spots WHERE id=?`, id).Scan(&x, &y); err != nil {
		t.Fatal(err)
	}
	if x != 11.5 || y != 48.1 {
		t.Fatalf("x=%v y=%v", x, y)
	}
	needle := fmt.Sprintf(`"id":%d,`, id)
	in := e.do(t, "GET", "/spots?south=48&west=11&north=48.2&east=12", "")
	if !strings.Contains(in.Body.String(), needle) {
		t.Fatalf("not in new bbox: %s", in.Body)
	}
	old := e.do(t, "GET", "/spots?south=49.9&west=9.9&north=50.1&east=10.1", "")
	if strings.Contains(old.Body.String(), needle) {
		t.Fatalf("still in old bbox: %s", old.Body)
	}
}

func TestPatchSpotHideAndList(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	id := newSpot(t, e.db, owner, "Visible", "active")
	needle := fmt.Sprintf(`"id":%d,`, id)
	const bbox = "/spots?south=49&west=9&north=51&east=11"
	if !strings.Contains(e.do(t, "GET", bbox, "").Body.String(), needle) {
		t.Fatal("precondition: spot not in public list")
	}
	e.expect(t, e.patchSpot(t, id, `{"status":"hidden"}`), 200, "")
	if strings.Contains(e.do(t, "GET", bbox, "").Body.String(), needle) {
		t.Fatal("hidden spot in public list")
	}
	e.expect(t, e.do(t, "GET", fmt.Sprintf("/spots/%d", id), ""), 404, "not_found")
	var list struct {
		Items []spotOut `json:"items"`
	}
	decode(t, e.do(t, "GET", "/admin/spots?status=hidden", e.tok), &list)
	if len(list.Items) != 1 || list.Items[0].ID != id || list.Items[0].Description != "d" {
		t.Fatalf("admin list: %+v", list.Items)
	}
	// hidden spots can be edited, and restored
	e.expect(t, e.patchSpot(t, id, `{"title":"Back again","status":"active"}`), 200, "")
	if c := e.do(t, "GET", fmt.Sprintf("/spots/%d", id), "").Code; c != 200 {
		t.Fatalf("public get = %d", c)
	}
}

// ---- reports ----

func TestDeleteReport(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	r1, r2 := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, owner, "S", "active")
	a := report(t, e.db, r1, "spot", sp, "x")
	b := report(t, e.db, r2, "spot", sp, "y")
	path := func(id uint64) string { return fmt.Sprintf("/admin/reports/%d", id) }
	if c := e.do(t, "DELETE", path(a), e.tok).Code; c != 204 {
		t.Fatalf("delete = %d", c)
	}
	e.expect(t, e.do(t, "DELETE", path(a), e.tok), 404, "not_found")
	e.expect(t, e.do(t, "DELETE", "/admin/reports/zz", e.tok), 404, "not_found")
	var n int
	_ = e.db.QueryRow(`SELECT COUNT(*) FROM reports WHERE id=?`, b).Scan(&n)
	if n != 1 {
		t.Fatal("other report removed")
	}
}

// reportVia files a report through the real route.
func (e *env) reportVia(t *testing.T, user uint64, typ string, target uint64) {
	t.Helper()
	body := fmt.Sprintf(`{"target_type":"%s","target_id":%d,"reason":"bad"}`, typ, target)
	w := e.send(t, "POST", "/reports", testutil.Token(t, user), body)
	if w.Code >= 300 {
		t.Fatalf("report: %d %s", w.Code, w.Body)
	}
}

func statusOf(t *testing.T, db *sql.DB, table string, id uint64) string {
	t.Helper()
	var s string
	if err := db.QueryRow(`SELECT status FROM `+table+` WHERE id=?`, id).Scan(&s); err != nil {
		t.Fatal(err)
	}
	return s
}

func countReports(t *testing.T, db *sql.DB, typ string, id uint64) int {
	t.Helper()
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM reports WHERE target_type=? AND target_id=?`, typ, id).Scan(&n)
	return n
}

func (e *env) dismiss(t *testing.T, body string) *httptest.ResponseRecorder {
	return e.send(t, "POST", "/admin/reports/dismiss", e.tok, body)
}

func TestDismissSpotAndUpdate(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	reporters := []uint64{testutil.NewUser(t, e.db), testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)}

	// spot without restore
	sp := newSpot(t, e.db, owner, "Spot A", "active")
	for _, r := range reporters {
		e.reportVia(t, r, "spot", sp)
	}
	if statusOf(t, e.db, "spots", sp) != "hidden" {
		t.Fatal("not auto-hidden")
	}
	w := e.dismiss(t, fmt.Sprintf(`{"target_type":"spot","target_id":%d}`, sp))
	e.expect(t, w, 200, "")
	if !strings.Contains(w.Body.String(), `"removed":3`) {
		t.Fatalf("body %s", w.Body)
	}
	if countReports(t, e.db, "spot", sp) != 0 || statusOf(t, e.db, "spots", sp) != "hidden" {
		t.Fatal("dismiss without restore wrong")
	}

	// spot with restore
	sp2 := newSpot(t, e.db, owner, "Spot B", "active")
	for _, r := range reporters {
		e.reportVia(t, r, "spot", sp2)
	}
	w = e.dismiss(t, fmt.Sprintf(`{"target_type":"spot","target_id":%d,"restore":true}`, sp2))
	e.expect(t, w, 200, "")
	if !strings.Contains(w.Body.String(), `"removed":3`) || statusOf(t, e.db, "spots", sp2) != "active" || countReports(t, e.db, "spot", sp2) != 0 {
		t.Fatalf("restore wrong: %s", w.Body)
	}

	// update with restore
	up := newUpdate(t, e.db, sp2, owner, "body")
	for _, r := range reporters {
		e.reportVia(t, r, "update", up)
	}
	if statusOf(t, e.db, "spot_updates", up) != "hidden" {
		t.Fatal("update not auto-hidden")
	}
	w = e.dismiss(t, fmt.Sprintf(`{"target_type":"update","target_id":%d,"restore":true}`, up))
	e.expect(t, w, 200, "")
	if !strings.Contains(w.Body.String(), `"removed":3`) || statusOf(t, e.db, "spot_updates", up) != "active" {
		t.Fatalf("update restore wrong: %s", w.Body)
	}

	// no reports: removed 0, still restores an existing target
	exec(t, e.db, `UPDATE spots SET status='hidden' WHERE id=?`, sp2)
	w = e.dismiss(t, fmt.Sprintf(`{"target_type":"spot","target_id":%d,"restore":true}`, sp2))
	e.expect(t, w, 200, "")
	if !strings.Contains(w.Body.String(), `"removed":0`) || statusOf(t, e.db, "spots", sp2) != "active" {
		t.Fatalf("zero case: %s", w.Body)
	}
	w = e.dismiss(t, `{"target_type":"spot","target_id":999999}`)
	e.expect(t, w, 200, "")
	if !strings.Contains(w.Body.String(), `"removed":0`) {
		t.Fatal(w.Body)
	}
	// restore on a missing target is 404
	e.expect(t, e.dismiss(t, `{"target_type":"spot","target_id":999999,"restore":true}`), 404, "not_found")
	e.expect(t, e.dismiss(t, `{"target_type":"update","target_id":999999,"restore":true}`), 404, "not_found")
	e.expect(t, e.dismiss(t, `{"target_type":"spot","target_id":0,"restore":true}`), 404, "not_found")
	// invalid input
	e.expect(t, e.dismiss(t, `{"target_type":"user","target_id":1}`), 400, "invalid_target")
	e.expect(t, e.dismiss(t, `{"target_id":1}`), 400, "invalid_target")
	e.expect(t, e.dismiss(t, `junk`), 400, "invalid_body")
}
