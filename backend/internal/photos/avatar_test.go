package photos_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"mime/multipart"
	"net/http/httptest"
	"net/textproto"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/photos"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/testutil"
)

const mediaPrefix = "http://test/api/v1/media/"

func pngBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewNRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.NRGBA{uint8(x), 50, uint8(y), 128}) // with alpha
		}
	}
	var b bytes.Buffer
	if err := png.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

// avatarReq sends method /api/v1/me/avatar with data in multipart field
// field (no body when data is nil).
func avatarReq(t *testing.T, e env, method, token, field string, data []byte) *httptest.ResponseRecorder {
	t.Helper()
	var body bytes.Buffer
	req := httptest.NewRequest(method, "/api/v1/me/avatar", nil)
	if data != nil {
		mw := multipart.NewWriter(&body)
		hdr := textproto.MIMEHeader{}
		hdr.Set("Content-Disposition", `form-data; name="`+field+`"; filename="me.jpg"`)
		hdr.Set("Content-Type", "image/jpeg")
		pw, _ := mw.CreatePart(hdr)
		pw.Write(data)
		mw.Close()
		req = httptest.NewRequest(method, "/api/v1/me/avatar", &body)
		req.Header.Set("Content-Type", mw.FormDataContentType())
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	return rec
}

func putAvatar(t *testing.T, e env, data []byte) string {
	t.Helper()
	rec := avatarReq(t, e, "PUT", testutil.Token(t, e.uid), "photo", data)
	if rec.Code != 200 {
		t.Fatalf("PUT /me/avatar: %d %s", rec.Code, rec.Body)
	}
	var out struct {
		AvatarURL string `json:"avatar_url"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	if !strings.HasPrefix(out.AvatarURL, mediaPrefix+"avatars/") || !strings.HasSuffix(out.AvatarURL, ".jpg") {
		t.Fatalf("avatar_url = %q", out.AvatarURL)
	}
	return out.AvatarURL
}

func avatarKey(t *testing.T, db *sql.DB, uid uint64) sql.NullString {
	t.Helper()
	var k sql.NullString
	if err := db.QueryRow(`SELECT avatar_key FROM users WHERE id = ?`, uid).Scan(&k); err != nil {
		t.Fatal(err)
	}
	return k
}

func fileOf(e env, url string) string {
	return filepath.Join(e.dir, filepath.FromSlash(strings.TrimPrefix(url, mediaPrefix)))
}

func media(e env, url string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, httptest.NewRequest("GET", strings.TrimPrefix(url, "http://test"), nil))
	return rec
}

// assertSquareJPEG checks that the stored file is a 384x384 JPEG.
func assertSquareJPEG(t *testing.T, path string) {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(b))
	if err != nil || format != "jpeg" {
		t.Fatalf("stored avatar: format %q err %v", format, err)
	}
	if cfg.Width != photos.AvatarEdge || cfg.Height != photos.AvatarEdge || photos.AvatarEdge != 384 {
		t.Fatalf("stored avatar is %dx%d, want 384x384", cfg.Width, cfg.Height)
	}
}

func TestAvatarUploadJPEGIsCroppedToSquare(t *testing.T) {
	e := setup(t)
	url := putAvatar(t, e, jpegBytes(t, 900, 500))
	assertSquareJPEG(t, fileOf(e, url))
	if k := avatarKey(t, e.db, e.uid); !k.Valid || mediaPrefix+k.String != url {
		t.Fatalf("avatar_key = %+v, url %q", k, url)
	}
	if rec := media(e, url); rec.Code != 200 || !strings.HasPrefix(rec.Header().Get("Content-Type"), "image/jpeg") {
		t.Fatalf("GET avatar: %d %q", rec.Code, rec.Header().Get("Content-Type"))
	}
	// not a photo: nothing in the photos table
	var n int
	e.db.QueryRow(`SELECT COUNT(*) FROM photos`).Scan(&n)
	if n != 0 {
		t.Fatalf("%d photo rows after avatar upload", n)
	}
}

func TestAvatarUploadPNGIsScaledToSquare(t *testing.T) {
	e := setup(t)
	url := putAvatar(t, e, pngBytes(t, 120, 300)) // small and tall: cropped and scaled up
	assertSquareJPEG(t, fileOf(e, url))
}

func TestAvatarCentreCrop(t *testing.T) {
	// left third red, middle third green, right third blue: the square crop
	// of a 3:1 image is the green middle.
	img := image.NewRGBA(image.Rect(0, 0, 900, 300))
	for y := 0; y < 300; y++ {
		for x := 0; x < 900; x++ {
			c := color.RGBA{0, 200, 0, 255}
			if x < 300 {
				c = color.RGBA{200, 0, 0, 255}
			} else if x >= 600 {
				c = color.RGBA{0, 0, 200, 255}
			}
			img.Set(x, y, c)
		}
	}
	var src bytes.Buffer
	png.Encode(&src, img)
	out, err := photos.NormalizeAvatar(context.Background(), &src, photos.MaxUploadBytes)
	if err != nil {
		t.Fatal(err)
	}
	dec, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	for _, x := range []int{10, 192, 373} {
		r, g, b, _ := dec.At(x, 192).RGBA()
		if g>>8 < 150 || r>>8 > 60 || b>>8 > 60 {
			t.Fatalf("pixel %d = %d,%d,%d, want green", x, r>>8, g>>8, b>>8)
		}
	}
}

func TestAvatarReplaceDeletesOldFile(t *testing.T) {
	e := setup(t)
	first := putAvatar(t, e, jpegBytes(t, 400, 400))
	second := putAvatar(t, e, jpegBytes(t, 500, 400))
	if first == second {
		t.Fatal("the new avatar must get a new key")
	}
	if _, err := os.Stat(fileOf(e, first)); !os.IsNotExist(err) {
		t.Fatalf("old avatar file still there: %v", err)
	}
	if rec := media(e, first); rec.Code != 404 {
		t.Fatalf("old avatar URL: %d, want 404", rec.Code)
	}
	assertSquareJPEG(t, fileOf(e, second))
	if rec := media(e, second); rec.Code != 200 {
		t.Fatalf("new avatar URL: %d", rec.Code)
	}
}

func TestAvatarUploadErrorsMatchPhotos(t *testing.T) {
	e := setup(t)
	tok := testutil.Token(t, e.uid)
	if rec := avatarReq(t, e, "PUT", tok, "photo", []byte("not an image at all")); rec.Code != 415 || errCode(rec) != "unsupported_type" {
		t.Fatalf("text: %d %s", rec.Code, rec.Body)
	}
	big := append(jpegBytes(t, 10, 10), bytes.Repeat([]byte{0}, photos.MaxUploadBytes)...)
	if rec := avatarReq(t, e, "PUT", tok, "photo", big); rec.Code != 413 || errCode(rec) != "too_large" {
		t.Fatalf("too big: %d %s", rec.Code, rec.Body)
	}
	if rec := avatarReq(t, e, "PUT", tok, "file", jpegBytes(t, 10, 10)); rec.Code != 400 || errCode(rec) != "file_required" {
		t.Fatalf("wrong field: %d %s", rec.Code, rec.Body)
	}
	if rec := avatarReq(t, e, "PUT", "", "photo", jpegBytes(t, 10, 10)); rec.Code != 401 {
		t.Fatalf("no token: %d", rec.Code)
	}
	if rec := avatarReq(t, e, "DELETE", "", "", nil); rec.Code != 401 {
		t.Fatalf("DELETE without token: %d", rec.Code)
	}
	if k := avatarKey(t, e.db, e.uid); k.Valid {
		t.Fatalf("failed uploads set avatar_key %q", k.String)
	}
	entries, _ := os.ReadDir(e.dir)
	if len(entries) != 0 {
		t.Fatalf("failed uploads left files: %v", entries)
	}
}

func TestAvatarDeleteIsIdempotent(t *testing.T) {
	e := setup(t)
	tok := testutil.Token(t, e.uid)
	url := putAvatar(t, e, jpegBytes(t, 300, 300))
	for i := 0; i < 2; i++ {
		if rec := avatarReq(t, e, "DELETE", tok, "", nil); rec.Code != 204 {
			t.Fatalf("DELETE #%d: %d %s", i+1, rec.Code, rec.Body)
		}
	}
	if k := avatarKey(t, e.db, e.uid); k.Valid {
		t.Fatalf("avatar_key still %q", k.String)
	}
	if _, err := os.Stat(fileOf(e, url)); !os.IsNotExist(err) {
		t.Fatalf("avatar file still there: %v", err)
	}
	if rec := media(e, url); rec.Code != 404 {
		t.Fatalf("deleted avatar URL: %d", rec.Code)
	}
}

func TestAvatarSharesThePhotoUploadLimit(t *testing.T) {
	db := testutil.NewDB(t)
	dir := t.TempDir()
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: dir, PublicBaseURL: "http://test"}
	cfg.Limits.Uploads = ratelimit.Rule{N: 2, Per: time.Hour}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { photos.Mount(r, app.Deps{DB: db, Cfg: cfg}) })
	e := env{h: r, db: db, dir: dir, uid: testutil.NewUser(t, db)}
	tok := testutil.Token(t, e.uid)
	if rec := upload(t, e, tok, "image/jpeg", jpegBytes(t, 20, 20)); rec.Code != 201 {
		t.Fatalf("photo: %d", rec.Code)
	}
	putAvatar(t, e, jpegBytes(t, 20, 20))
	if rec := avatarReq(t, e, "PUT", tok, "photo", jpegBytes(t, 20, 20)); rec.Code != 429 {
		t.Fatalf("third upload in the hour: %d, want 429", rec.Code)
	}
}

func TestCleanupNeverTouchesAvatars(t *testing.T) {
	e := setup(t)
	url := putAvatar(t, e, jpegBytes(t, 300, 300))
	// an unattached, old photo, which the cleanup must remove
	rec := upload(t, e, testutil.Token(t, e.uid), "image/jpeg", jpegBytes(t, 50, 50))
	if rec.Code != 201 {
		t.Fatalf("photo: %d", rec.Code)
	}
	var p resp
	json.Unmarshal(rec.Body.Bytes(), &p)
	e.db.Exec(`UPDATE photos SET created_at = NOW() - INTERVAL 3 DAY`)

	n, err := photos.CleanupUnattached(context.Background(), e.db,
		photos.NewLocalStorage(e.dir, "http://test/api/v1/media"), time.Hour)
	if err != nil || n != 1 {
		t.Fatalf("cleanup: n=%d err=%v", n, err)
	}
	if _, err := os.Stat(fileOf(e, p.URL)); !os.IsNotExist(err) {
		t.Fatalf("unattached photo survived cleanup: %v", err)
	}
	if _, err := os.Stat(fileOf(e, url)); err != nil {
		t.Fatalf("cleanup removed the avatar: %v", err)
	}
	if k := avatarKey(t, e.db, e.uid); !k.Valid {
		t.Fatal("cleanup cleared avatar_key")
	}
	if rec := media(e, url); rec.Code != 200 {
		t.Fatalf("avatar after cleanup: %d", rec.Code)
	}
}
