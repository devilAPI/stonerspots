package server_test

import (
	"strconv"
	"testing"

	"stonerspots/backend/internal/testutil"
)

// 0017 makes display names unique without failing on existing duplicates.
func TestUniqueNamesMigrationRenamesDuplicates(t *testing.T) {
	d, dsn := testutil.NewEmptyDB(t)
	migrateTo(t, dsn, 16)
	ids := map[string]int64{}
	for _, u := range []struct{ email, name string }{
		{"a@x.de", "Max"}, {"b@x.de", "max "}, {"c@x.de", "MAX"}, {"d@x.de", "  "}, {"e@x.de", "Eva"},
	} {
		res, err := d.Exec(`INSERT INTO users (email, password_hash, display_name) VALUES (?, 'x', ?)`, u.email, u.name)
		if err != nil {
			t.Fatal(err)
		}
		ids[u.email], _ = res.LastInsertId()
	}
	migrateTo(t, dsn, 17)
	name := func(email string) string {
		var n string
		if err := d.QueryRow(`SELECT display_name FROM users WHERE email = ?`, email).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	got := map[string]string{}
	for _, e := range []string{"a@x.de", "b@x.de", "c@x.de", "d@x.de", "e@x.de"} {
		got[e] = name(e)
	}
	want := map[string]string{
		"a@x.de": "Max", // the oldest keeps it
		"b@x.de": "max " + strconv.FormatInt(ids["b@x.de"], 10),
		"c@x.de": "MAX " + strconv.FormatInt(ids["c@x.de"], 10),
		"d@x.de": "user " + strconv.FormatInt(ids["d@x.de"], 10),
		"e@x.de": "Eva",
	}
	for e, w := range want {
		if got[e] != w {
			t.Errorf("%s: %q, want %q", e, got[e], w)
		}
	}
	if _, err := d.Exec(`INSERT INTO users (email, password_hash, display_name) VALUES ('f@x.de', 'x', 'eva')`); err == nil {
		t.Fatal("duplicate name accepted after the migration")
	}
}
