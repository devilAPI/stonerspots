package admin_test

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"stonerspots/backend/internal/testutil"
)

// photoFile writes a w x h JPEG (and a thumb) below the upload dir, red in
// the top-left quarter and white elsewhere, and returns the photo row id.
func photoFile(t *testing.T, e *env, owner, update uint64, name string, w, h int) uint64 {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			c := color.RGBA{255, 255, 255, 255}
			if x < w/2 && y < h/2 {
				c = color.RGBA{255, 0, 0, 255}
			}
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}
	key, thumb := "2026/01/"+name+".jpg", "2026/01/"+name+"_thumb.jpg"
	for _, k := range []string{key, thumb} {
		p := filepath.Join(e.upload, filepath.FromSlash(k))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, buf.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return uint64(exec(t, e.db, "INSERT INTO photos (user_id, `key`, thumb_key, width, height, status, update_id) VALUES (?, ?, ?, ?, ?, 'approved', ?)",
		owner, key, thumb, w, h, update))
}

func (e *env) rotatePhoto(t *testing.T, id uint64, body string) *httptest.ResponseRecorder {
	t.Helper()
	return e.send(t, "POST", "/admin/photos/"+itoa(id)+"/rotate", e.tok, body)
}

func exists(dir, key string) bool {
	_, err := os.Stat(filepath.Join(dir, filepath.FromSlash(key)))
	return err == nil
}

func TestAdminRotatePhoto(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	up := newUpdate(t, e.db, newSpot(t, e.db, owner, "Bench", "active"), owner, "")
	id := photoFile(t, e, owner, up, "a", 40, 20)

	w := e.rotatePhoto(t, id, `{"degrees":90}`)
	e.expect(t, w, 200, "")
	var out struct {
		URL      string `json:"url"`
		ThumbURL string `json:"thumb_url"`
		Width    int    `json:"width"`
		Height   int    `json:"height"`
	}
	decode(t, w, &out)
	if out.Width != 20 || out.Height != 40 {
		t.Fatalf("size %dx%d", out.Width, out.Height)
	}
	var key, thumb string
	var width, height int
	if err := e.db.QueryRow("SELECT `key`, thumb_key, width, height FROM photos WHERE id=?", id).Scan(&key, &thumb, &width, &height); err != nil {
		t.Fatal(err)
	}
	// new keys, so cached copies of the old URLs are never shown as rotated
	if key == "2026/01/a.jpg" || width != 20 || height != 40 || !strings.HasSuffix(out.URL, "/"+key) || !strings.HasSuffix(out.ThumbURL, "/"+thumb) {
		t.Fatalf("row %s %s %dx%d, response %+v", key, thumb, width, height, out)
	}
	if exists(e.upload, "2026/01/a.jpg") || exists(e.upload, "2026/01/a_thumb.jpg") || !exists(e.upload, thumb) {
		t.Fatal("old files kept or thumb missing")
	}
	f, err := os.Open(filepath.Join(e.upload, filepath.FromSlash(key)))
	if err != nil {
		t.Fatal(err)
	}
	img, err := jpeg.Decode(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}
	// clockwise: the red top-left quarter ends up top-right
	if r, g, _, _ := img.At(15, 2).RGBA(); r < 0xc000 || g > 0x4000 {
		t.Fatal("top-right is not red")
	}
	if _, g, _, _ := img.At(2, 2).RGBA(); g < 0xc000 {
		t.Fatal("top-left is not white")
	}

	e.expect(t, e.rotatePhoto(t, id, `{"degrees":45}`), 400, "invalid_rotation")
	e.expect(t, e.rotatePhoto(t, id, `{"degrees":"90"}`), 400, "invalid_body")
	e.expect(t, e.rotatePhoto(t, id, `{}`), 400, "empty_patch")
	e.expect(t, e.rotatePhoto(t, 999999, `{"degrees":90}`), 404, "not_found")
}

func TestAdminDeletePhoto(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	up := newUpdate(t, e.db, newSpot(t, e.db, owner, "Bench", "active"), owner, "")
	a := photoFile(t, e, owner, up, "a", 8, 8)
	b := photoFile(t, e, owner, up, "b", 8, 8)

	e.expect(t, e.do(t, "DELETE", "/admin/photos/"+itoa(a), e.tok), 204, "")
	if count(t, e.db, "SELECT COUNT(*) FROM photos WHERE id=?", a) != 0 || exists(e.upload, "2026/01/a.jpg") || exists(e.upload, "2026/01/a_thumb.jpg") {
		t.Fatal("photo a remains")
	}
	// an update needs text or photos
	e.expect(t, e.do(t, "DELETE", "/admin/photos/"+itoa(b), e.tok), 409, "last_photo")
	if !exists(e.upload, "2026/01/b.jpg") {
		t.Fatal("refused delete removed the file")
	}
	exec(t, e.db, "UPDATE spot_updates SET body='text' WHERE id=?", up)
	e.expect(t, e.do(t, "DELETE", "/admin/photos/"+itoa(b), e.tok), 204, "")
	e.expect(t, e.do(t, "DELETE", "/admin/photos/"+itoa(b), e.tok), 404, "not_found")

	user := testutil.Token(t, owner)
	e.expect(t, e.do(t, "DELETE", "/admin/photos/1", user), 403, "")
}
