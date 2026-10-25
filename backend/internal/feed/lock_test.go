package feed_test

import (
	"encoding/json"
	"fmt"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestLockedSpotBlocksUpdatesForNonAdmins(t *testing.T) {
	db, h, _ := setupDir(t)
	author := testutil.NewUser(t, db)
	admin := testutil.NewUser(t, db)
	if _, err := db.Exec(`UPDATE users SET is_admin=1 WHERE id=?`, admin); err != nil {
		t.Fatal(err)
	}
	s := newSpot(t, db, author, 48, 11, 0)
	path := fmt.Sprintf("/spots/%d/updates", s)

	// before locking, the author's own update
	rec := call(t, h, "POST", path, author, `{"body":"first"}`)
	if rec.Code != 201 {
		t.Fatal(rec.Code, rec.Body)
	}
	own := decode(t, rec).ID
	if _, err := db.Exec(`UPDATE spots SET locked=1 WHERE id=?`, s); err != nil {
		t.Fatal(err)
	}

	errCode := func(b []byte) string {
		var e struct {
			Error struct {
				Code string `json:"code"`
			} `json:"error"`
		}
		json.Unmarshal(b, &e)
		return e.Error.Code
	}
	for _, c := range []struct {
		method, path, body string
	}{
		{"POST", path, `{"body":"new"}`},
		{"PATCH", fmt.Sprintf("/updates/%d", own), `{"body":"changed"}`},
		{"DELETE", fmt.Sprintf("/updates/%d", own), ``},
	} {
		rec := call(t, h, c.method, c.path, author, c.body)
		if rec.Code != 403 || errCode(rec.Body.Bytes()) != "spot_locked" {
			t.Fatalf("%s %s: %d %s", c.method, c.path, rec.Code, rec.Body)
		}
	}
	var body string
	db.QueryRow(`SELECT body FROM spot_updates WHERE id=?`, own).Scan(&body)
	if body != "first" {
		t.Fatal("changed despite lock:", body)
	}

	// admins may still post and change their own updates
	rec = call(t, h, "POST", path, admin, `{"body":"admin note"}`)
	if rec.Code != 201 {
		t.Fatal(rec.Code, rec.Body)
	}
	mine := decode(t, rec).ID
	if rec := call(t, h, "PATCH", fmt.Sprintf("/updates/%d", mine), admin, `{"body":"admin edit"}`); rec.Code != 200 {
		t.Fatal(rec.Code, rec.Body)
	}

	// unlocking lifts it
	db.Exec(`UPDATE spots SET locked=0 WHERE id=?`, s)
	if rec := call(t, h, "POST", path, author, `{"body":"again"}`); rec.Code != 201 {
		t.Fatal(rec.Code, rec.Body)
	}
}
