package admin_test

import (
	"context"
	"fmt"
	"testing"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/testutil"
)

func newComment(t *testing.T, e *env, update, user uint64, body string) uint64 {
	return uint64(exec(t, e.db, `INSERT INTO comments (update_id, user_id, body) VALUES (?, ?, ?)`, update, user, body))
}

func TestCommentReportsHideListAndDelete(t *testing.T) {
	e := setup(t)
	owner, author := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)
	sp := newSpot(t, e.db, owner, "Talked", "active")
	up := newUpdate(t, e.db, sp, owner, "upd")
	c := newComment(t, e, up, author, "rude words")
	keep := newComment(t, e, up, author, "fine")

	for i := 0; i < 3; i++ {
		e.reportVia(t, testutil.NewTrustedUser(t, e.db), "comment", c)
	}
	if statusOf(t, e.db, "comments", c) != "hidden" {
		t.Fatal("comment not auto-hidden after 3 reports")
	}
	// a hidden comment cannot be reported any more, like a hidden review
	w := e.send(t, "POST", "/reports", testutil.Token(t, owner), fmt.Sprintf(`{"target_type":"comment","target_id":%d}`, c))
	e.expect(t, w, 404, "not_found")
	report(t, e.db, owner, "comment", keep, "")

	w = e.do(t, "GET", "/admin/reports?limit=100", e.tok)
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	var pg struct {
		Items []struct {
			TargetType  string `json:"target_type"`
			TargetID    uint64 `json:"target_id"`
			ReportCount int    `json:"report_count"`
			Target      struct {
				Exists   bool    `json:"exists"`
				SpotID   uint64  `json:"spot_id"`
				Title    string  `json:"title"`
				Status   string  `json:"status"`
				Body     string  `json:"body"`
				Author   userRef `json:"author"`
				UpdateID uint64  `json:"update_id"`
			} `json:"target"`
		} `json:"items"`
	}
	decode(t, w, &pg)
	seen := 0
	for _, it := range pg.Items {
		if it.TargetType != "comment" || it.TargetID != c {
			continue
		}
		seen++
		tg := it.Target
		if !tg.Exists || tg.SpotID != sp || tg.Title != "Talked" || tg.Status != "hidden" || tg.Body != "rude words" ||
			tg.Author.ID != author || tg.UpdateID != up || it.ReportCount != 3 {
			t.Fatalf("comment item: %+v", it)
		}
	}
	if seen != 3 {
		t.Fatalf("seen %d comment reports", seen)
	}

	// the comment author has 4 reports received
	exec(t, e.db, `UPDATE users SET display_name='CommentAuthor' WHERE id=?`, author)
	var users struct {
		Items []struct {
			ReportsReceived int `json:"reports_received"`
		} `json:"items"`
	}
	decode(t, e.do(t, "GET", "/admin/users?q=CommentAuthor", e.tok), &users)
	if len(users.Items) != 1 || users.Items[0].ReportsReceived != 4 {
		t.Fatalf("reports_received: %+v", users.Items)
	}

	w = e.do(t, "DELETE", fmt.Sprintf("/admin/comments/%d", c), e.tok)
	if w.Code != 204 {
		t.Fatalf("delete: %d %s", w.Code, w.Body)
	}
	if count(t, e.db, `SELECT COUNT(*) FROM comments WHERE id=?`, c) != 0 || countReports(t, e.db, "comment", c) != 0 {
		t.Fatal("comment or its reports remain")
	}
	if countReports(t, e.db, "comment", keep) != 1 {
		t.Fatal("other comment's report touched")
	}
	e.expect(t, e.do(t, "DELETE", fmt.Sprintf("/admin/comments/%d", c), e.tok), 404, "not_found")
	e.expect(t, e.do(t, "DELETE", "/admin/comments/abc", e.tok), 404, "not_found")
	e.expect(t, e.do(t, "DELETE", fmt.Sprintf("/admin/comments/%d", keep), testutil.Token(t, owner)), 403, "")
}

func TestDismissComment(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	up := newUpdate(t, e.db, newSpot(t, e.db, owner, "S", "active"), owner, "u")
	c := newComment(t, e, up, owner, "x")
	reporters := []uint64{testutil.NewUser(t, e.db), testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)}
	for _, r := range reporters {
		e.reportVia(t, r, "comment", c)
	}
	w := e.dismiss(t, fmt.Sprintf(`{"target_type":"comment","target_id":%d,"restore":true}`, c))
	if w.Code != 200 || statusOf(t, e.db, "comments", c) != "active" || countReports(t, e.db, "comment", c) != 0 {
		t.Fatalf("restore: %d %s", w.Code, w.Body)
	}
}

func TestDeletingParentsRemovesCommentReports(t *testing.T) {
	e := setup(t)
	owner, commenter, rep := testutil.NewUser(t, e.db), testutil.NewUser(t, e.db), testutil.NewUser(t, e.db)

	// spot deleted by an admin
	sp := newSpot(t, e.db, owner, "Doomed", "active")
	c1 := newComment(t, e, newUpdate(t, e.db, sp, owner, "u"), commenter, "x")
	report(t, e.db, rep, "comment", c1, "")
	if w := e.do(t, "DELETE", fmt.Sprintf("/admin/spots/%d", sp), e.tok); w.Code != 204 {
		t.Fatalf("spot: %d %s", w.Code, w.Body)
	}
	if countReports(t, e.db, "comment", c1) != 0 {
		t.Fatal("report of a comment on a deleted spot remains")
	}

	// update deleted by an admin
	keepSpot := newSpot(t, e.db, owner, "Keep", "active")
	up := newUpdate(t, e.db, keepSpot, owner, "u")
	c2 := newComment(t, e, up, commenter, "x")
	report(t, e.db, rep, "comment", c2, "")
	if w := e.do(t, "DELETE", fmt.Sprintf("/admin/updates/%d", up), e.tok); w.Code != 204 {
		t.Fatalf("update: %d %s", w.Code, w.Body)
	}
	if countReports(t, e.db, "comment", c2) != 0 {
		t.Fatal("report of a comment on a deleted update remains")
	}

	// commenter's account deleted
	up2 := newUpdate(t, e.db, keepSpot, owner, "u2")
	c3 := newComment(t, e, up2, commenter, "x")
	c4 := newComment(t, e, up2, rep, "stays")
	report(t, e.db, rep, "comment", c3, "")
	report(t, e.db, owner, "comment", c4, "")
	if err := auth.DeleteUser(context.Background(), e.db, e.upload, commenter); err != nil {
		t.Fatal(err)
	}
	if countReports(t, e.db, "comment", c3) != 0 || countReports(t, e.db, "comment", c4) != 1 {
		t.Fatal("user delete: wrong comment reports left")
	}

	// update author's account deleted: comments under their updates go too
	if err := auth.DeleteUser(context.Background(), e.db, e.upload, owner); err != nil {
		t.Fatal(err)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM reports WHERE target_type='comment'`); n != 0 {
		t.Fatalf("%d comment reports left", n)
	}
}
