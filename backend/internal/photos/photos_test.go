package photos_test

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/photos"
	"stonerspots/backend/internal/testutil"
)

type env struct {
	h   http.Handler
	db  *sql.DB
	dir string
	uid uint64
}

func setup(t *testing.T) env {
	t.Helper()
	db := testutil.NewDB(t)
	dir := t.TempDir()
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: dir, PublicBaseURL: "http://test"}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { photos.Mount(r, app.Deps{DB: db, Cfg: cfg}) })
	return env{h: r, db: db, dir: dir, uid: testutil.NewUser(t, db)}
}

func jpegBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x), uint8(y), 100, 255})
		}
	}
	var b bytes.Buffer
	if err := jpeg.Encode(&b, img, nil); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

// withGPSExif inserts an APP1 Exif segment (containing GPS-ish text) after SOI.
func withGPSExif(jpg []byte) []byte {
	payload := append([]byte("Exif\x00\x00"), []byte("MM\x00\x2a GPSLatitude 52.5200 GPSLongitude 13.4050")...)
	seg := []byte{0xFF, 0xE1, byte((len(payload) + 2) >> 8), byte((len(payload) + 2) & 0xFF)}
	seg = append(seg, payload...)
	out := append([]byte{}, jpg[:2]...)
	out = append(out, seg...)
	return append(out, jpg[2:]...)
}

func upload(t *testing.T, e env, token, contentType string, data []byte) *httptest.ResponseRecorder {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	hdr := textproto.MIMEHeader{}
	hdr.Set("Content-Disposition", `form-data; name="file"; filename="x.jpg"`)
	hdr.Set("Content-Type", contentType)
	pw, _ := mw.CreatePart(hdr)
	pw.Write(data)
	mw.Close()
	req := httptest.NewRequest("POST", "/api/v1/photos", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	return rec
}

func errCode(rec *httptest.ResponseRecorder) string {
	var b struct{ Error struct{ Code string } }
	json.Unmarshal(rec.Body.Bytes(), &b)
	return b.Error.Code
}

type resp struct {
	ID       uint64 `json:"id"`
	URL      string `json:"url"`
	ThumbURL string `json:"thumb_url"`
}

func TestUploadJPEGReturnsURLs(t *testing.T) {
	e := setup(t)
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", jpegBytes(t, 300, 200))
	if rec.Code != 201 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var r resp
	json.Unmarshal(rec.Body.Bytes(), &r)
	if r.ID == 0 || !strings.HasPrefix(r.URL, "http://test/api/v1/media/") || !strings.HasPrefix(r.ThumbURL, "http://test/api/v1/media/") {
		t.Fatalf("bad response %+v", r)
	}
	var key, thumb string
	var w, h int
	var upd sql.NullInt64
	if err := e.db.QueryRow("SELECT `key`, thumb_key, width, height, update_id FROM photos WHERE id=?", r.ID).Scan(&key, &thumb, &w, &h, &upd); err != nil {
		t.Fatal(err)
	}
	if w != 300 || h != 200 || upd.Valid {
		t.Fatalf("row w=%d h=%d upd=%v", w, h, upd)
	}
	if !strings.HasSuffix(key, ".jpg") || strings.Count(key, "/") != 2 {
		t.Fatalf("key %q", key)
	}
	// served right away: photos are moderated after the fact
	get := func() *httptest.ResponseRecorder {
		g := httptest.NewRecorder()
		e.h.ServeHTTP(g, httptest.NewRequest("GET", strings.TrimPrefix(r.URL, "http://test"), nil))
		return g
	}
	if g := get(); g.Code != 200 || g.Body.Len() == 0 {
		t.Fatalf("media get: %d", g.Code)
	}
	if _, err := e.db.Exec("UPDATE photos SET status = 'rejected' WHERE id = ?", r.ID); err != nil {
		t.Fatal(err)
	}
	if g := get(); g.Code != 404 {
		t.Fatalf("rejected photo served: %d", g.Code)
	}
	if _, err := os.Stat(filepath.Join(e.dir, filepath.FromSlash(thumb))); err != nil {
		t.Fatal(err)
	}
}

func TestRejectsTextFileWithJPEGContentType(t *testing.T) {
	e := setup(t)
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", []byte("hello, definitely not an image"))
	if rec.Code != 415 || errCode(rec) != "unsupported_type" {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
}

func TestRejectsOver8MB(t *testing.T) {
	e := setup(t)
	big := append(jpegBytes(t, 10, 10), make([]byte, 9<<20)...)
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", big)
	if rec.Code != 413 || errCode(rec) != "too_large" {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
}

func TestMissingFile(t *testing.T) {
	e := setup(t)
	req := httptest.NewRequest("POST", "/api/v1/photos", strings.NewReader(""))
	req.Header.Set("Authorization", "Bearer "+testutil.Token(t, e.uid))
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 400 || errCode(rec) != "file_required" {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
}

func TestStripsGPSExif(t *testing.T) {
	e := setup(t)
	in := withGPSExif(jpegBytes(t, 100, 100))
	if !bytes.Contains(in, []byte("Exif")) {
		t.Fatal("fixture lacks Exif")
	}
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", in)
	if rec.Code != 201 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var r resp
	json.Unmarshal(rec.Body.Bytes(), &r)
	var key, thumb string
	e.db.QueryRow("SELECT `key`, thumb_key FROM photos WHERE id=?", r.ID).Scan(&key, &thumb)
	for _, k := range []string{key, thumb} {
		out, err := os.ReadFile(filepath.Join(e.dir, filepath.FromSlash(k)))
		if err != nil {
			t.Fatal(err)
		}
		if bytes.Contains(out, []byte("Exif")) || bytes.Contains(out, []byte("GPS")) || bytes.Contains(out, []byte{0xFF, 0xE1}) {
			t.Fatalf("%s still contains metadata", k)
		}
	}
}

func TestLongEdgeResizedTo1600(t *testing.T) {
	e := setup(t)
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", jpegBytes(t, 3200, 1000))
	if rec.Code != 201 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var r resp
	json.Unmarshal(rec.Body.Bytes(), &r)
	var key, thumb string
	var w, h int
	e.db.QueryRow("SELECT `key`, thumb_key, width, height FROM photos WHERE id=?", r.ID).Scan(&key, &thumb, &w, &h)
	if w != 1600 || h != 500 {
		t.Fatalf("size %dx%d", w, h)
	}
	for k, want := range map[string]int{key: 1600, thumb: 400} {
		f, _ := os.Open(filepath.Join(e.dir, filepath.FromSlash(k)))
		cfg, _, err := image.DecodeConfig(f)
		f.Close()
		if err != nil || cfg.Width != want {
			t.Fatalf("%s width %d err %v", k, cfg.Width, err)
		}
	}
}

func TestRequiresAuth(t *testing.T) {
	e := setup(t)
	rec := upload(t, e, "", "image/jpeg", jpegBytes(t, 10, 10))
	if rec.Code != 401 {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestMediaRejectsTraversal(t *testing.T) {
	e := setup(t)
	req := httptest.NewRequest("GET", "/api/v1/media/..%2f..%2fetc/passwd", nil)
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code == 200 {
		t.Fatal("traversal served")
	}
}
