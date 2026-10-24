package admin_test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func newReview(t *testing.T, e *env, spot, user uint64, rating int, body string) uint64 {
	return uint64(exec(t, e.db, `INSERT INTO spot_reviews (spot_id, user_id, rating, body) VALUES (?, ?, ?, ?)`, spot, user, rating, body))
}

func TestReviewReportsListShape(t *testing.T) {
	e := setup(t)
	owner, author := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, owner, "Rated", "active")
	rv := newReview(t, e, sp, author, 4, "nice place")
	gone := newReview(t, e, sp, testutil.NewUser(t, e.db), 2, "bye")
	var rs []uint64
	for i := 0; i < 3; i++ {
		u := testutil.NewUser(t, e.db)
		rs = append(rs, u)
		e.reportVia(t, u, "review", rv)
	}
	e.reportVia(t, rs[0], "review", gone)
	exec(t, e.db, `DELETE FROM spot_reviews WHERE id=?`, gone) // orphan report remains
	updID := newUpdate(t, e.db, sp, owner, "upd")
	report(t, e.db, rs[0], "update", updID, "")

	w := e.do(t, "GET", "/admin/reports?limit=100", e.tok)
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	var pg struct {
		Items []struct {
			TargetType  string `json:"target_type"`
			TargetID    uint64 `json:"target_id"`
			ReportCount int    `json:"report_count"`
			Target      struct {
				Exists bool    `json:"exists"`
				SpotID uint64  `json:"spot_id"`
				Title  string  `json:"title"`
				Status string  `json:"status"`
				Body   string  `json:"body"`
				Rating *int    `json:"rating"`
				Author userRef `json:"author"`
			} `json:"target"`
		} `json:"items"`
	}
	decode(t, w, &pg)
	seenReview, seenGone, seenUpd := 0, false, false
	for _, it := range pg.Items {
		switch {
		case it.TargetType == "review" && it.TargetID == rv:
			seenReview++
			tg := it.Target
			if !tg.Exists || tg.SpotID != sp || tg.Title != "Rated" || tg.Status != "hidden" || tg.Body != "nice place" ||
				tg.Rating == nil || *tg.Rating != 4 || tg.Author.ID != author || it.ReportCount != 3 {
				t.Fatalf("review item: %+v", it)
			}
		case it.TargetType == "review" && it.TargetID == gone:
			seenGone = true
			if it.Target.Exists || it.Target.Body != "" {
				t.Fatalf("gone: %+v", it)
			}
		case it.TargetType == "update":
			seenUpd = true
			if it.Target.Rating == nil || *it.Target.Rating != 0 || !it.Target.Exists {
				t.Fatalf("update item: %+v", it)
			}
		}
	}
	if seenReview != 3 || !seenGone || !seenUpd {
		t.Fatalf("seen %d %v %v", seenReview, seenGone, seenUpd)
	}
}

func TestDeleteReview(t *testing.T) {
	e := setup(t)
	owner, a1, a2 := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, owner, "S", "active")
	r1 := newReview(t, e, sp, a1, 5, "x")
	r2 := newReview(t, e, sp, a2, 1, "y")
	report(t, e.db, a2, "review", r1, "")
	report(t, e.db, a1, "review", r2, "")
	w := e.do(t, "DELETE", fmt.Sprintf("/admin/reviews/%d", r1), e.tok)
	if w.Code != 204 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if count(t, e.db, `SELECT COUNT(*) FROM spot_reviews WHERE id=?`, r1) != 0 || countReports(t, e.db, "review", r1) != 0 {
		t.Fatal("review or reports remain")
	}
	if count(t, e.db, `SELECT COUNT(*) FROM spot_reviews WHERE id=?`, r2) != 1 || countReports(t, e.db, "review", r2) != 1 {
		t.Fatal("other review touched")
	}
	w = e.do(t, "GET", fmt.Sprintf("/spots/%d/reviews", sp), "")
	var out struct {
		Summary struct {
			Count int     `json:"count"`
			Avg   float64 `json:"avg"`
		} `json:"summary"`
	}
	decode(t, w, &out)
	if out.Summary.Count != 1 || out.Summary.Avg != 1 {
		t.Fatalf("summary %+v", out.Summary)
	}
	w = e.do(t, "DELETE", fmt.Sprintf("/admin/reviews/%d", r1), e.tok)
	e.expect(t, w, 404, "not_found")
	e.expect(t, e.do(t, "DELETE", "/admin/reviews/abc", e.tok), 404, "not_found")
}

func TestDeleteUpdate(t *testing.T) {
	e := setup(t)
	au, other := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, au, "S", "active")
	u := newUpdate(t, e.db, sp, au, "b")
	ku := newUpdate(t, e.db, sp, au, "k")
	exec(t, e.db, `UPDATE spot_updates SET status='hidden' WHERE id=?`, u)
	write := func(name string) string {
		if err := os.WriteFile(filepath.Join(e.upload, name), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		return name
	}
	photo := func(upd uint64, k, tk string) {
		exec(t, e.db, "INSERT INTO photos (user_id, `key`, thumb_key, width, height, update_id) VALUES (?, ?, ?, 1, 1, ?)", au, k, tk, upd)
	}
	photo(u, write("a.jpg"), write("a_t.jpg"))
	photo(ku, write("k.jpg"), write("k_t.jpg"))
	outside := filepath.Join(filepath.Dir(e.upload), "outside-"+filepath.Base(e.upload))
	if err := os.WriteFile(outside, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(outside)
	photo(u, "../"+filepath.Base(outside), "")
	report(t, e.db, other, "update", u, "")
	report(t, e.db, other, "update", ku, "")

	w := e.do(t, "DELETE", fmt.Sprintf("/admin/updates/%d", u), e.tok)
	if w.Code != 204 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if count(t, e.db, `SELECT COUNT(*) FROM spot_updates WHERE id=?`, u) != 0 ||
		count(t, e.db, "SELECT COUNT(*) FROM photos WHERE `key` IN ('a.jpg') OR `key` LIKE '../%'") != 0 ||
		countReports(t, e.db, "update", u) != 0 {
		t.Fatal("update, photos or reports remain")
	}
	for _, f := range []string{"a.jpg", "a_t.jpg"} {
		if _, err := os.Stat(filepath.Join(e.upload, f)); !os.IsNotExist(err) {
			t.Errorf("%s still exists", f)
		}
	}
	for _, f := range []string{"k.jpg", "k_t.jpg"} {
		if _, err := os.Stat(filepath.Join(e.upload, f)); err != nil {
			t.Errorf("%s removed", f)
		}
	}
	if _, err := os.Stat(outside); err != nil {
		t.Error("outside file removed")
	}
	if count(t, e.db, `SELECT COUNT(*) FROM spot_updates WHERE id=?`, ku) != 1 || countReports(t, e.db, "update", ku) != 1 {
		t.Fatal("other update touched")
	}
	e.expect(t, e.do(t, "DELETE", fmt.Sprintf("/admin/updates/%d", u), e.tok), 404, "not_found")
	e.expect(t, e.do(t, "DELETE", "/admin/updates/abc", e.tok), 404, "not_found")
}

func TestDismissReview(t *testing.T) {
	e := setup(t)
	owner, author := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, owner, "S", "active")
	reporters := []uint64{testutil.NewUser(t, e.db), testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)}
	rv := newReview(t, e, sp, author, 3, "x")
	for _, r := range reporters {
		e.reportVia(t, r, "review", rv)
	}
	if statusOf(t, e.db, "spot_reviews", rv) != "hidden" {
		t.Fatal("not auto-hidden")
	}
	w := e.dismiss(t, fmt.Sprintf(`{"target_type":"review","target_id":%d}`, rv))
	if w.Code != 200 || statusOf(t, e.db, "spot_reviews", rv) != "hidden" || countReports(t, e.db, "review", rv) != 0 {
		t.Fatalf("no restore: %d %s", w.Code, w.Body)
	}
	for _, r := range reporters {
		report(t, e.db, r, "review", rv, "")
	}
	w = e.dismiss(t, fmt.Sprintf(`{"target_type":"review","target_id":%d,"restore":true}`, rv))
	if w.Code != 200 || statusOf(t, e.db, "spot_reviews", rv) != "active" || countReports(t, e.db, "review", rv) != 0 {
		t.Fatalf("restore: %d %s", w.Code, w.Body)
	}
	w = e.dismiss(t, `{"target_type":"review","target_id":999999,"restore":true}`)
	e.expect(t, w, 404, "not_found")
}

func TestDeleteSpotRemovesReviewReports(t *testing.T) {
	e := setup(t)
	owner, rev, rep := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, owner, "Doomed", "active")
	keep := newSpot(t, e.db, owner, "Keep", "active")
	rv := newReview(t, e, sp, rev, 3, "x")
	kr := newReview(t, e, keep, rev, 3, "x")
	report(t, e.db, rep, "review", rv, "")
	report(t, e.db, rep, "review", kr, "")
	if w := e.do(t, "DELETE", fmt.Sprintf("/admin/spots/%d", sp), e.tok); w.Code != 204 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM reports`); n != 1 || countReports(t, e.db, "review", kr) != 1 {
		t.Fatalf("reports left = %d", n)
	}
}
