package server_test

import (
	"database/sql"
	"testing"

	"stonerspots/backend/internal/testutil"
)

// 0027 moves every comment from its update to the update's spot, and rolls
// back by putting each comment under its spot's newest update.
func TestSpotCommentsMigration(t *testing.T) {
	d, dsn := testutil.NewEmptyDB(t)
	migrateTo(t, dsn, 24)
	ins := func(q string, args ...any) int64 {
		t.Helper()
		res, err := d.Exec(q, args...)
		if err != nil {
			t.Fatal(err)
		}
		id, _ := res.LastInsertId()
		return id
	}
	u := ins(`INSERT INTO users (email, password_hash, display_name) VALUES ('a@x.de', 'x', 'A')`)
	spot := func() int64 {
		return ins(`INSERT INTO spots (user_id, title, description, location)
			VALUES (?, 's', 'd', ST_GeomFromText('POINT(10 50)'))`, u)
	}
	s1, s2 := spot(), spot()
	u1 := ins(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'a')`, s1, u)
	u2 := ins(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'b')`, s1, u)
	u3 := ins(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'c')`, s2, u)
	c1 := ins(`INSERT INTO comments (update_id, user_id, body) VALUES (?, ?, 'x')`, u1, u)
	c2 := ins(`INSERT INTO comments (update_id, user_id, body) VALUES (?, ?, 'y')`, u3, u)
	ins(`INSERT INTO activity (user_id, actor_id, kind, spot_id, update_id, comment_id) VALUES (?, ?, 'comment', ?, ?, ?)`,
		u, u, s1, u1, c1)

	migrateTo(t, dsn, 27)
	spotOf := func(c int64) int64 {
		t.Helper()
		var s int64
		if err := d.QueryRow(`SELECT spot_id FROM comments WHERE id = ?`, c).Scan(&s); err != nil {
			t.Fatal(err)
		}
		return s
	}
	if spotOf(c1) != s1 || spotOf(c2) != s2 {
		t.Fatalf("spots: %d %d", spotOf(c1), spotOf(c2))
	}
	var n int
	if err := d.QueryRow(`SELECT COUNT(*) FROM information_schema.columns
		WHERE table_schema = DATABASE() AND table_name = 'comments' AND column_name = 'update_id'`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("update_id still there: %d %v", n, err)
	}
	// the old activity row keeps its update
	if err := d.QueryRow(`SELECT COUNT(*) FROM activity WHERE comment_id = ? AND update_id = ?`, c1, u1).Scan(&n); err != nil || n != 1 {
		t.Fatalf("activity row: %d %v", n, err)
	}
	// comments now outlive updates, and a spot without updates takes them
	if _, err := d.Exec(`DELETE FROM spot_updates WHERE id = ?`, u3); err != nil {
		t.Fatal(err)
	}
	if spotOf(c2) != s2 {
		t.Fatal("comment went with the update")
	}
	c3 := ins(`INSERT INTO comments (spot_id, user_id, body) VALUES (?, ?, 'z')`, s1, u)
	ins(`INSERT INTO reports (user_id, target_type, target_id) VALUES (?, 'comment', ?)`, u, c2)

	migrateTo(t, dsn, 24)
	updateOf := func(c int64) sql.NullInt64 {
		t.Helper()
		var up sql.NullInt64
		err := d.QueryRow(`SELECT update_id FROM comments WHERE id = ?`, c).Scan(&up)
		if err != nil && err != sql.ErrNoRows {
			t.Fatal(err)
		}
		return up
	}
	// under the spot's newest update; c2's spot has none left, so it goes
	if got := updateOf(c1); got.Int64 != u2 {
		t.Fatalf("c1 under %v, want %d", got, u2)
	}
	if got := updateOf(c3); got.Int64 != u2 {
		t.Fatalf("c3 under %v, want %d", got, u2)
	}
	if updateOf(c2).Valid {
		t.Fatal("c2 survived without an update")
	}
	if err := d.QueryRow(`SELECT COUNT(*) FROM reports WHERE target_type = 'comment'`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("reports left: %d %v", n, err)
	}
	migrateTo(t, dsn, 27)
}
