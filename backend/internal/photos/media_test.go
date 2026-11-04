package photos_test

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"stonerspots/backend/internal/testutil"
)

// newSpot inserts an active spot of e.uid and returns its id.
func newSpot(t *testing.T, e env) int64 {
	t.Helper()
	res, err := e.db.Exec(`INSERT INTO spots (user_id, title, description, location)
		VALUES (?, 't', 'd', ST_GeomFromText('POINT(13.4 52.5)'))`, e.uid)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return id
}

// attach posts photo on a new active update of a new active spot and
// returns the update and spot ids.
func attach(t *testing.T, e env, photo uint64) (update, spot int64) {
	t.Helper()
	spot = newSpot(t, e)
	res, err := e.db.Exec(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'x')`, spot, e.uid)
	if err != nil {
		t.Fatal(err)
	}
	update, _ = res.LastInsertId()
	if _, err := e.db.Exec(`UPDATE photos SET update_id = ? WHERE id = ?`, update, photo); err != nil {
		t.Fatal(err)
	}
	return update, spot
}

func uploadOK(t *testing.T, e env) resp {
	t.Helper()
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", jpegBytes(t, 60, 40))
	if rec.Code != 201 {
		t.Fatalf("upload: %d %s", rec.Code, rec.Body)
	}
	var r resp
	json.Unmarshal(rec.Body.Bytes(), &r)
	return r
}

func mustExec(t *testing.T, e env, q string, args ...any) {
	t.Helper()
	if _, err := e.db.Exec(q, args...); err != nil {
		t.Fatal(err)
	}
}

// codes returns the status of GET for the full photo and its thumb.
func codes(e env, r resp) [2]int {
	return [2]int{media(e, r.URL).Code, media(e, r.ThumbURL).Code}
}

func TestMediaServesOnlyPhotosOfVisibleUpdates(t *testing.T) {
	e := setup(t)
	ok, gone := [2]int{200, 200}, [2]int{404, 404}

	// unattached (just uploaded, not posted yet): nobody, not even with a token
	p := uploadOK(t, e)
	if c := codes(e, p); c != gone {
		t.Fatalf("unattached photo: %v, want 404", c)
	}
	req := httptest.NewRequest("GET", strings.TrimPrefix(p.URL, "http://test"), nil)
	req.Header.Set("Authorization", "Bearer "+testutil.Token(t, e.uid))
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 404 {
		t.Fatalf("unattached photo for its uploader: %d, want 404", rec.Code)
	}

	update, spot := attach(t, e, p.ID)
	if c := codes(e, p); c != ok {
		t.Fatalf("posted photo: %v", c)
	}

	steps := []struct {
		name     string
		hide     string
		show     string
		hiddenID int64
	}{
		{"rejected photo", `UPDATE photos SET status = 'rejected' WHERE id = ?`, `UPDATE photos SET status = 'approved' WHERE id = ?`, int64(p.ID)},
		{"hidden update", `UPDATE spot_updates SET status = 'hidden' WHERE id = ?`, `UPDATE spot_updates SET status = 'active' WHERE id = ?`, update},
		{"hidden spot", `UPDATE spots SET status = 'hidden' WHERE id = ?`, `UPDATE spots SET status = 'active' WHERE id = ?`, spot},
	}
	for _, s := range steps {
		mustExec(t, e, s.hide, s.hiddenID)
		if c := codes(e, p); c != gone {
			t.Fatalf("%s: %v, want 404", s.name, c)
		}
		mustExec(t, e, s.show, s.hiddenID)
		if c := codes(e, p); c != ok {
			t.Fatalf("%s shown again: %v", s.name, c)
		}
	}

	// a deleted update leaves its photos unattached (ON DELETE SET NULL)
	mustExec(t, e, `DELETE FROM spot_updates WHERE id = ?`, update)
	if c := codes(e, p); c != gone {
		t.Fatalf("photo of a deleted update: %v, want 404", c)
	}
	// and a deleted spot takes its updates along
	q := uploadOK(t, e)
	_, spot2 := attach(t, e, q.ID)
	mustExec(t, e, `DELETE FROM spots WHERE id = ?`, spot2)
	if c := codes(e, q); c != gone {
		t.Fatalf("photo of a deleted spot: %v, want 404", c)
	}
}

func TestMediaCacheHeaders(t *testing.T) {
	e := setup(t)
	p := uploadOK(t, e)
	attach(t, e, p.ID)
	rec := media(e, p.URL)
	if rec.Code != 200 {
		t.Fatalf("GET: %d", rec.Code)
	}
	cc := rec.Header().Get("Cache-Control")
	if cc != "public, max-age=3600" || strings.Contains(cc, "immutable") {
		t.Fatalf("Cache-Control %q", cc)
	}
	lm := rec.Header().Get("Last-Modified")
	if lm == "" || rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("headers %v", rec.Header())
	}
	// conditional requests still work
	req := httptest.NewRequest("GET", strings.TrimPrefix(p.URL, "http://test"), nil)
	req.Header.Set("If-Modified-Since", lm)
	rec = httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 304 {
		t.Fatalf("If-Modified-Since: %d, want 304", rec.Code)
	}
}

func TestMediaUnknownKeysAre404(t *testing.T) {
	e := setup(t)
	for _, path := range []string{
		"/api/v1/media/2026/01/00000000000000000000000000000000.jpg",
		"/api/v1/media/2026/01/00000000000000000000000000000000_thumb.jpg",
		"/api/v1/media/avatars/2026/01/00000000000000000000000000000000.jpg",
		"/api/v1/media/2026/01/x.png",
	} {
		rec := httptest.NewRecorder()
		e.h.ServeHTTP(rec, httptest.NewRequest("GET", path, nil))
		if rec.Code != 404 {
			t.Fatalf("%s: %d", path, rec.Code)
		}
	}
}

// The lookups by key and thumb_key have unique indexes (migration 0025).
func TestPhotoKeysAreUniquelyIndexed(t *testing.T) {
	e := setup(t)
	for col, index := range map[string]string{"key": "uq_photos_key", "thumb_key": "uq_photos_thumb_key"} {
		var n int
		err := e.db.QueryRow(`SELECT COUNT(*) FROM information_schema.statistics
			WHERE table_schema = DATABASE() AND table_name = 'photos'
			  AND index_name = ? AND column_name = ? AND non_unique = 0 AND seq_in_index = 1`, index, col).Scan(&n)
		if err != nil || n != 1 {
			t.Fatalf("unique index %s on photos.%s: n=%d err=%v", index, col, n, err)
		}
	}
	// a duplicate key is refused
	p := uploadOK(t, e)
	var key string
	e.db.QueryRow("SELECT `key` FROM photos WHERE id = ?", p.ID).Scan(&key)
	_, err := e.db.Exec("INSERT INTO photos (user_id, `key`, thumb_key, width, height) VALUES (?, ?, 'other_thumb.jpg', 1, 1)", e.uid, key)
	if err == nil {
		t.Fatal("duplicate photo key accepted")
	}
}
