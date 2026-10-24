package auth_test

import "testing"

func TestDeleteAccountWithReviews(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	o := register(t, e.h, "b@example.com")
	res, err := e.db.Exec("INSERT INTO spots (user_id, title, description, location) VALUES (?, 't', 'd', ST_GeomFromText('POINT(1 1)'))", o.User.ID)
	if err != nil {
		t.Fatal(err)
	}
	spot, _ := res.LastInsertId()
	// u reviews o's spot; o reviews a spot of u's
	res, _ = e.db.Exec("INSERT INTO spots (user_id, title, description, location) VALUES (?, 't', 'd', ST_GeomFromText('POINT(2 2)'))", u.User.ID)
	spotU, _ := res.LastInsertId()
	for _, q := range [][]any{{spot, u.User.ID}, {spotU, o.User.ID}} {
		if _, err := e.db.Exec("INSERT INTO spot_reviews (spot_id, user_id, rating, body) VALUES (?, ?, 4, 'ok')", q...); err != nil {
			t.Fatal(err)
		}
	}
	if rec := do(t, e.h, "POST", "/me/delete", u.AccessToken, map[string]any{"password": pw}); rec.Code != 204 {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	if n := count(t, e.db, "SELECT COUNT(*) FROM spot_reviews"); n != 0 {
		t.Fatalf("reviews left: %d", n)
	}
}
