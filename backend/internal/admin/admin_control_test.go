package admin_test

import (
	"net/http/httptest"
	"reflect"
	"strconv"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestAdminSpotOwnerAndLock(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	other := testutil.NewUser(t, e.db)
	id := newSpot(t, e.db, owner, "Bench", "active")

	var out struct {
		Locked bool `json:"locked"`
		Author struct {
			ID uint64 `json:"id"`
		} `json:"author"`
	}
	w := e.patchSpot(t, id, `{"owner_id":`+itoa(other)+`,"locked":true}`)
	e.expect(t, w, 200, "")
	decode(t, w, &out)
	if out.Author.ID != other || !out.Locked {
		t.Fatalf("%s", w.Body)
	}
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE id=? AND user_id=? AND locked=1`, id, other); n != 1 {
		t.Fatal("not stored")
	}
	w = e.patchSpot(t, id, `{"locked":false}`)
	decode(t, w, &out)
	if out.Locked || out.Author.ID != other {
		t.Fatalf("unlock: %s", w.Body)
	}

	e.expect(t, e.patchSpot(t, id, `{"owner_id":999999}`), 400, "invalid_owner")
	e.expect(t, e.patchSpot(t, id, `{"owner_id":"x"}`), 400, "invalid_body")
	e.expect(t, e.patchSpot(t, id, `{"locked":"yes"}`), 400, "invalid_body")
	// locking is the locked field; status can't hold "locked"
	e.expect(t, e.patchSpot(t, id, `{"status":"locked"}`), 400, "invalid_status")
	e.expect(t, e.do(t, "GET", "/admin/spots?status=locked", e.tok), 400, "invalid_status")
	// a failed owner change leaves the other fields alone too
	e.expect(t, e.patchSpot(t, id, `{"title":"Never","owner_id":999999}`), 400, "invalid_owner")
	if n := count(t, e.db, `SELECT COUNT(*) FROM spots WHERE id=? AND title='Bench'`, id); n != 1 {
		t.Fatal("partial write")
	}

	// the admin list shows the lock
	e.patchSpot(t, id, `{"locked":true}`)
	var list struct {
		Items []struct {
			ID     uint64 `json:"id"`
			Locked bool   `json:"locked"`
		} `json:"items"`
	}
	decode(t, e.do(t, "GET", "/admin/spots", e.tok), &list)
	if len(list.Items) != 1 || !list.Items[0].Locked {
		t.Fatalf("%+v", list)
	}
}

func (e *env) patchUpdate(t *testing.T, id uint64, body string) *httptest.ResponseRecorder {
	t.Helper()
	return e.send(t, "PATCH", "/admin/updates/"+itoa(id), e.tok, body)
}

func TestAdminEditUpdate(t *testing.T) {
	e := setup(t)
	author := testutil.NewUser(t, e.db)
	spot := newSpot(t, e.db, author, "Bench", "active")
	up := newUpdate(t, e.db, spot, author, "old text")
	exec(t, e.db, `UPDATE spots SET locked=1 WHERE id=?`, spot) // admins ignore the lock

	e.expect(t, e.patchUpdate(t, up, `{"body":"  fixed text  ","tag":"dirty"}`), 204, "")
	var body, tag, status string
	var edited *string
	e.db.QueryRow(`SELECT body, tag, status, edited_at FROM spot_updates WHERE id=?`, up).Scan(&body, &tag, &status, &edited)
	if body != "fixed text" || tag != "dirty" || status != "active" || edited == nil {
		t.Fatalf("%q %q %q %v", body, tag, status, edited)
	}

	// hiding only changes the status
	e.expect(t, e.patchUpdate(t, up, `{"status":"hidden"}`), 204, "")
	e.db.QueryRow(`SELECT body, status FROM spot_updates WHERE id=?`, up).Scan(&body, &status)
	if body != "fixed text" || status != "hidden" {
		t.Fatal(body, status)
	}
	// a hidden update can still be edited and restored
	e.expect(t, e.patchUpdate(t, up, `{"status":"active","body":"again"}`), 204, "")

	e.expect(t, e.patchUpdate(t, up, `{"tag":"bogus"}`), 400, "invalid_tag")
	e.expect(t, e.patchUpdate(t, up, `{"status":"gone"}`), 400, "invalid_status")
	e.expect(t, e.patchUpdate(t, up, `{"status":"locked"}`), 400, "invalid_status")
	e.expect(t, e.patchUpdate(t, up, `{"body":"   "}`), 400, "invalid_body")
	e.expect(t, e.patchUpdate(t, up, `{}`), 400, "empty_patch")
	e.expect(t, e.patchUpdate(t, 999999, `{"body":"x"}`), 404, "not_found")

	// admins only
	other := testutil.NewUser(t, e.db)
	e.expect(t, e.send(t, "PATCH", "/admin/updates/"+itoa(up), testutil.Token(t, other), `{"body":"hack"}`), 403, "forbidden")
	e.expect(t, e.send(t, "PATCH", "/admin/updates/"+itoa(up), testutil.Token(t, author), `{"body":"hack"}`), 403, "forbidden")
}

func TestAdminTagCatalog(t *testing.T) {
	e := setup(t)
	type tag struct {
		Tag       string `json:"tag"`
		NameDE    string `json:"name_de"`
		NameEN    string `json:"name_en"`
		Icon      string `json:"icon"`
		Sort      int    `json:"sort"`
		SpotCount int    `json:"spot_count"`
	}
	keys := func(path, tok string) []string {
		var l []tag
		decode(t, e.do(t, "GET", path, tok), &l)
		out := []string{}
		for _, x := range l {
			out = append(out, x.Tag)
		}
		return out
	}
	builtIn := []string{"roof", "seating", "view", "quiet", "shade", "water", "lit"}
	if got := keys("/tags", ""); !reflect.DeepEqual(got, builtIn) {
		t.Fatalf("public catalog: %v", got)
	}

	// create: goes last unless a sort is given
	w := e.send(t, "POST", "/admin/tags", e.tok, `{"tag":"fire_pit","name_de":" Feuerstelle ","name_en":"Fire pit","icon":"fire"}`)
	e.expect(t, w, 201, "")
	var created tag
	decode(t, w, &created)
	if created.NameDE != "Feuerstelle" || created.Sort != 80 {
		t.Fatalf("%s", w.Body)
	}
	e.expect(t, e.send(t, "POST", "/admin/tags", e.tok, `{"tag":"bridge","name_de":"Brücke","name_en":"Bridge","icon":"bridge","sort":5}`), 201, "")
	if got := keys("/tags", ""); !reflect.DeepEqual(got, append(append([]string{"bridge"}, builtIn...), "fire_pit")) {
		t.Fatalf("order: %v", got)
	}

	// validation
	for body, code := range map[string]string{
		`{"tag":"fire_pit","name_de":"x","name_en":"x","icon":"x"}`: "tag_taken",
		`{"tag":"Fire","name_de":"x","name_en":"x","icon":"x"}`:     "invalid_tag",
		`{"tag":"a","name_de":"x","name_en":"x","icon":"x"}`:        "invalid_tag",
		`{"tag":"ok_tag","name_de":"","name_en":"x","icon":"x"}`:    "invalid_name",
		`{"tag":"ok_tag","name_de":"x","name_en":"x","icon":"A-B"}`: "invalid_icon",
		`{"tag":"ok_tag","name_de":"x","name_en":"x"}`:              "missing_field",
	} {
		w := e.send(t, "POST", "/admin/tags", e.tok, body)
		want := 400
		if code == "tag_taken" {
			want = 409
		}
		e.expect(t, w, want, code)
	}

	// the new tag works on spots right away, and counts are listed
	owner := testutil.NewUser(t, e.db)
	spot := newSpot(t, e.db, owner, "Fire place", "active")
	e.expect(t, e.patchSpot(t, spot, `{"tags":["fire_pit","roof"]}`), 200, "")
	var admin []tag
	decode(t, e.do(t, "GET", "/admin/tags", e.tok), &admin)
	for _, x := range admin {
		want := 0
		if x.Tag == "fire_pit" || x.Tag == "roof" {
			want = 1
		}
		if x.SpotCount != want {
			t.Fatalf("%s count %d", x.Tag, x.SpotCount)
		}
	}

	// rename / re-icon / reorder
	w = e.send(t, "PATCH", "/admin/tags/fire_pit", e.tok, `{"name_en":"Fireplace","icon":"campfire","sort":1}`)
	e.expect(t, w, 200, "")
	var patched tag
	decode(t, w, &patched)
	if patched.NameEN != "Fireplace" || patched.NameDE != "Feuerstelle" || patched.Icon != "campfire" || patched.Sort != 1 {
		t.Fatalf("%s", w.Body)
	}
	if got := keys("/tags", "")[0]; got != "fire_pit" {
		t.Fatalf("first = %s", got)
	}
	e.expect(t, e.send(t, "PATCH", "/admin/tags/nope", e.tok, `{"name_en":"x"}`), 404, "not_found")
	e.expect(t, e.send(t, "PATCH", "/admin/tags/fire_pit", e.tok, `{"name_en":""}`), 400, "invalid_name")

	// delete: gone from the catalog and from every spot
	e.expect(t, e.send(t, "DELETE", "/admin/tags/fire_pit", e.tok, ``), 204, "")
	if n := count(t, e.db, `SELECT COUNT(*) FROM spot_tags WHERE spot_id=?`, spot); n != 1 {
		t.Fatalf("spot tags left: %d", n)
	}
	e.expect(t, e.patchSpot(t, spot, `{"tags":["fire_pit"]}`), 400, "invalid_tags")
	e.expect(t, e.send(t, "DELETE", "/admin/tags/fire_pit", e.tok, ``), 404, "not_found")

	// admins only
	user := testutil.Token(t, owner)
	e.expect(t, e.do(t, "GET", "/admin/tags", user), 403, "forbidden")
	e.expect(t, e.send(t, "POST", "/admin/tags", user, `{"tag":"zz","name_de":"x","name_en":"x","icon":"x"}`), 403, "forbidden")
	e.expect(t, e.send(t, "DELETE", "/admin/tags/roof", user, ``), 403, "forbidden")
}

func itoa(n uint64) string { return strconv.FormatUint(n, 10) }
