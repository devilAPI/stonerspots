package server_test

import (
	"database/sql"
	"reflect"
	"testing"

	"github.com/golang-migrate/migrate/v4"
	migmysql "github.com/golang-migrate/migrate/v4/database/mysql"
	_ "github.com/golang-migrate/migrate/v4/source/file"

	"stonerspots/backend/internal/db"
	"stonerspots/backend/internal/testutil"
)

func migrateTo(t *testing.T, dsn string, version uint) {
	t.Helper()
	conn, err := db.Open(dsn)
	if err != nil {
		t.Fatal(err)
	}
	drv, err := migmysql.WithInstance(conn, &migmysql.Config{})
	if err != nil {
		t.Fatal(err)
	}
	m, err := migrate.NewWithDatabaseInstance("file://"+testutil.MigrationsDir(), "mysql", drv)
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	if err := m.Migrate(version); err != nil && err != migrate.ErrNoChange {
		t.Fatalf("migrate to %d: %v", version, err)
	}
}

func tagsOf(t *testing.T, d *sql.DB, id int64) []string {
	t.Helper()
	rows, err := d.Query(`SELECT tag FROM spot_tags WHERE spot_id = ? ORDER BY tag`, id)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var s string
		rows.Scan(&s)
		out = append(out, s)
	}
	return out
}

func hasCategoryColumn(d *sql.DB) int {
	var n int
	d.QueryRow(`SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'spots' AND column_name = 'category'`).Scan(&n)
	return n
}

func TestDropCategoriesMigrationConvertsLegacyToTags(t *testing.T) {
	d, dsn := testutil.NewEmptyDB(t)
	migrateTo(t, dsn, 9)
	if _, err := d.Exec(`INSERT INTO users (email, password_hash, display_name) VALUES ('a@b.c', 'x', 'A')`); err != nil {
		t.Fatal(err)
	}
	ids := map[string]int64{}
	for _, c := range []string{"bench", "river", "lake", "viewpoint", "forest", "park", "other"} {
		res, err := d.Exec(`INSERT INTO spots (user_id, title, description, category, location) VALUES (1, ?, '', ?, POINT(10, 50))`, "spot "+c, c)
		if err != nil {
			t.Fatal(err)
		}
		ids[c], _ = res.LastInsertId()
	}
	// Pre-existing tags must survive and not collide (INSERT IGNORE).
	d.Exec(`INSERT INTO spot_tags (spot_id, tag) VALUES (?, 'water'), (?, 'roof')`, ids["lake"], ids["bench"])

	migrateTo(t, dsn, 10)

	want := map[string][]string{
		"bench": {"roof", "seating"}, "river": {"water"}, "lake": {"water"}, "viewpoint": {"view"},
		"forest": {}, "park": {}, "other": {},
	}
	for c, w := range want {
		if got := tagsOf(t, d, ids[c]); !reflect.DeepEqual(got, w) {
			t.Errorf("%s tags = %v, want %v", c, got, w)
		}
	}
	if hasCategoryColumn(d) != 0 {
		t.Fatal("spots.category still exists")
	}
	var cnt int
	d.QueryRow(`SELECT COUNT(*) FROM spots`).Scan(&cnt)
	if cnt != 7 {
		t.Fatalf("spots lost: %d", cnt)
	}

	// Down re-adds the column (data not restorable); up works again.
	migrateTo(t, dsn, 9)
	if hasCategoryColumn(d) != 1 {
		t.Fatal("down must re-add category")
	}
	migrateTo(t, dsn, 10)
	if hasCategoryColumn(d) != 0 {
		t.Fatal("category back after re-up")
	}
}
