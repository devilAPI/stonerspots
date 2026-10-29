package admin_test

import (
	"os"
	"path/filepath"
	"slices"
	"testing"

	"stonerspots/backend/internal/testutil"
)

type bulkOut struct {
	Items []struct {
		ID     uint64   `json:"id"`
		Banned bool     `json:"banned"`
		Status string   `json:"status"`
		Locked bool     `json:"locked"`
		Tags   []string `json:"tags"`
	} `json:"items"`
	Deleted []uint64 `json:"deleted"`
	Skipped []struct {
		ID     uint64 `json:"id"`
		Reason string `json:"reason"`
	} `json:"skipped"`
}

func (e *env) bulk(t *testing.T, what, body string) bulkOut {
	t.Helper()
	w := e.send(t, "POST", "/admin/"+what+"/bulk", e.tok, body)
	e.expect(t, w, 200, "")
	var out bulkOut
	decode(t, w, &out)
	return out
}

func TestBulkUsers(t *testing.T) {
	e := setup(t)
	a := testutil.NewUser(t, e.db)
	b := testutil.NewUser(t, e.db)
	otherAdmin := testutil.NewUser(t, e.db)
	exec(t, e.db, `UPDATE users SET is_admin=1 WHERE id=?`, otherAdmin)
	exec(t, e.db, `INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at) VALUES (?, 'h', 'f', UTC_TIMESTAMP() + INTERVAL 1 DAY)`, a)

	body := `{"action":"ban","ids":[` + itoa(a) + `,` + itoa(b) + `,` + itoa(e.admin) + `,` + itoa(otherAdmin) + `,999999]}`
	out := e.bulk(t, "users", body)
	if len(out.Items) != 2 || !out.Items[0].Banned || !out.Items[1].Banned {
		t.Fatalf("items: %+v", out)
	}
	reasons := map[uint64]string{}
	for _, s := range out.Skipped {
		reasons[s.ID] = s.Reason
	}
	if reasons[e.admin] != "self" || reasons[otherAdmin] != "admin" || reasons[999999] != "not_found" {
		t.Fatalf("skipped: %+v", out.Skipped)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM users WHERE banned_at IS NOT NULL`); n != 2 {
		t.Fatalf("banned rows: %d", n)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM refresh_tokens WHERE user_id=? AND revoked_at IS NULL`, a); n != 0 {
		t.Fatal("sessions not ended")
	}
	// the list shows it
	var list struct {
		Items []struct {
			ID     uint64 `json:"id"`
			Banned bool   `json:"banned"`
		} `json:"items"`
	}
	decode(t, e.do(t, "GET", "/admin/users", e.tok), &list)
	for _, u := range list.Items {
		if u.Banned != (u.ID == a || u.ID == b) {
			t.Fatalf("list: %+v", list)
		}
	}

	out = e.bulk(t, "users", `{"action":"unban","ids":[`+itoa(a)+`]}`)
	if len(out.Items) != 1 || out.Items[0].Banned {
		t.Fatalf("unban: %+v", out)
	}

	// delete takes their spots and photo files along
	spot := newSpot(t, e.db, b, "Bench", "active")
	up := newUpdate(t, e.db, spot, b, "hi")
	if err := os.WriteFile(filepath.Join(e.upload, "p.jpg"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	exec(t, e.db, "INSERT INTO photos (user_id, `key`, thumb_key, width, height, update_id) VALUES (?, 'p.jpg', 'p.jpg', 1, 1, ?)", b, up)
	out = e.bulk(t, "users", `{"action":"delete","ids":[`+itoa(b)+`,`+itoa(e.admin)+`]}`)
	if !slices.Equal(out.Deleted, []uint64{b}) || len(out.Skipped) != 1 {
		t.Fatalf("delete: %+v", out)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE id=?`, spot); n != 0 {
		t.Fatal("spot kept")
	}
	if _, err := os.Stat(filepath.Join(e.upload, "p.jpg")); !os.IsNotExist(err) {
		t.Fatal("photo file kept")
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM users WHERE id=?`, e.admin); n != 1 {
		t.Fatal("deleted self")
	}

	e.expect(t, e.send(t, "POST", "/admin/users/bulk", e.tok, `{"action":"nuke","ids":[1]}`), 400, "invalid_action")
	e.expect(t, e.send(t, "POST", "/admin/users/bulk", e.tok, `{"action":"ban","ids":[]}`), 400, "invalid_ids")
	e.expect(t, e.send(t, "POST", "/admin/users/bulk", testutil.Token(t, a), `{"action":"ban","ids":[1]}`), 403, "")
}

func TestBulkSpots(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	s1 := newSpot(t, e.db, owner, "One", "active")
	s2 := newSpot(t, e.db, owner, "Two", "active")
	ids := `[` + itoa(s1) + `,` + itoa(s2) + `]`

	out := e.bulk(t, "spots", `{"action":"hide","ids":`+ids+`}`)
	if len(out.Items) != 2 || out.Items[0].Status != "hidden" {
		t.Fatalf("hide: %+v", out)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE status='hidden'`); n != 2 {
		t.Fatal("not hidden")
	}
	e.bulk(t, "spots", `{"action":"show","ids":`+ids+`}`)
	out = e.bulk(t, "spots", `{"action":"lock","ids":`+ids+`}`)
	if !out.Items[1].Locked {
		t.Fatalf("lock: %+v", out)
	}
	e.bulk(t, "spots", `{"action":"unlock","ids":`+ids+`}`)
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE status='active' AND locked=0`); n != 2 {
		t.Fatal("not shown/unlocked")
	}

	out = e.bulk(t, "spots", `{"action":"add_tag","tag":"water","ids":`+ids+`}`)
	if !slices.Equal(out.Items[0].Tags, []string{"water"}) {
		t.Fatalf("add_tag: %+v", out)
	}
	// adding again keeps one
	out = e.bulk(t, "spots", `{"action":"add_tag","tag":"water","ids":[`+itoa(s1)+`]}`)
	if !slices.Equal(out.Items[0].Tags, []string{"water"}) {
		t.Fatalf("add_tag twice: %+v", out)
	}
	out = e.bulk(t, "spots", `{"action":"remove_tag","tag":"water","ids":`+ids+`}`)
	if len(out.Items[0].Tags) != 0 || len(out.Items[1].Tags) != 0 {
		t.Fatalf("remove_tag: %+v", out)
	}
	e.expect(t, e.send(t, "POST", "/admin/spots/bulk", e.tok, `{"action":"add_tag","tag":"nope","ids":`+ids+`}`), 400, "invalid_tags")

	out = e.bulk(t, "spots", `{"action":"delete","ids":[`+itoa(s1)+`,999999]}`)
	if !slices.Equal(out.Deleted, []uint64{s1}) || len(out.Skipped) != 1 || out.Skipped[0].Reason != "not_found" {
		t.Fatalf("delete: %+v", out)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots`); n != 1 {
		t.Fatal("not deleted")
	}
}
