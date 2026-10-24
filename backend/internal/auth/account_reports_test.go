package auth_test

import "testing"

func TestDeleteAccountRemovesReportsAboutContent(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	o := register(t, e.h, "b@example.com")
	mk := func(q string, args ...any) int64 {
		res, err := e.db.Exec(q, args...)
		if err != nil {
			t.Fatal(err)
		}
		id, _ := res.LastInsertId()
		return id
	}
	const ins = "INSERT INTO spots (user_id, title, description, category, location) VALUES (?, 't', 'd', 'bench', ST_GeomFromText('POINT(1 1)'))"
	mine, theirs := mk(ins, u.User.ID), mk(ins, o.User.ID)
	myUpd := mk("INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'x')", theirs, u.User.ID)
	theirUpd := mk("INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'x')", theirs, o.User.ID)
	myRev := mk("INSERT INTO spot_reviews (spot_id, user_id, rating, body) VALUES (?, ?, 4, 'ok')", theirs, u.User.ID)
	theirRev := mk("INSERT INTO spot_reviews (spot_id, user_id, rating, body) VALUES (?, ?, 4, 'ok')", mine, o.User.ID)
	rep := func(typ string, id int64) {
		mk("INSERT INTO reports (user_id, target_type, target_id, reason) VALUES (?, ?, ?, '')", o.User.ID, typ, id)
	}
	rep("spot", mine)
	rep("update", myUpd)
	rep("review", myRev)
	rep("review", theirRev) // review by o on u's spot: cascades with u's spot
	rep("update", theirUpd) // survives
	rep("spot", theirs)     // survives
	if rec := do(t, e.h, "POST", "/me/delete", u.AccessToken, map[string]any{"password": pw}); rec.Code != 204 {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	if n := count(t, e.db, "SELECT COUNT(*) FROM reports"); n != 2 {
		t.Fatalf("reports left: %d, want 2", n)
	}
}
