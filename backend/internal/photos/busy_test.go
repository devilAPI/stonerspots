package photos

import (
	"bytes"
	"context"
	"mime/multipart"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/testutil"
)

func TestUploadAnswers503WhenBusy(t *testing.T) {
	resetSlots(t)
	db := testutil.NewDB(t)
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: t.TempDir(), PublicBaseURL: "http://test"}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { Mount(r, app.Deps{DB: db, Cfg: cfg}) })
	tok := testutil.Token(t, testutil.NewUser(t, db))

	send := func(path, field string) *httptest.ResponseRecorder {
		var body bytes.Buffer
		mw := multipart.NewWriter(&body)
		fw, _ := mw.CreateFormFile(field, "x.jpg")
		fw.Write(testJPEG(t, 32, 32))
		mw.Close()
		method := "POST"
		if path == "/api/v1/me/avatar" {
			method = "PUT"
		}
		req := httptest.NewRequest(method, path, &body)
		req.Header.Set("Content-Type", mw.FormDataContentType())
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		return rec
	}

	slotWait = 50 * time.Millisecond
	release, err := acquireDecodeSlots(context.Background(), maxConcurrentDecodes)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range [][2]string{{"/api/v1/photos", "file"}, {"/api/v1/me/avatar", "photo"}} {
		rec := send(c[0], c[1])
		if rec.Code != 503 || rec.Header().Get("Retry-After") == "" || !bytes.Contains(rec.Body.Bytes(), []byte(`"busy"`)) {
			t.Fatalf("%s while busy: %d %q %s", c[0], rec.Code, rec.Header().Get("Retry-After"), rec.Body)
		}
	}
	release()
	if rec := send("/api/v1/photos", "file"); rec.Code != 201 {
		t.Fatalf("after release: %d %s", rec.Code, rec.Body)
	}
}

func TestUploadRuleKeepsTheRateWithASmallBurst(t *testing.T) {
	for _, c := range []struct{ in, want ratelimit.Rule }{
		{ratelimit.Rule{N: 30, Per: time.Hour}, ratelimit.Rule{N: 5, Per: 10 * time.Minute}},
		{ratelimit.Rule{N: 60, Per: time.Hour}, ratelimit.Rule{N: 5, Per: 5 * time.Minute}},
		{ratelimit.Rule{N: 3, Per: time.Hour}, ratelimit.Rule{N: 3, Per: time.Hour}},
		{ratelimit.Rule{}, ratelimit.Rule{}},
	} {
		if got := uploadRule(c.in); got != c.want {
			t.Errorf("uploadRule(%+v) = %+v, want %+v", c.in, got, c.want)
		}
	}
}

func TestUploadBurstIsFive(t *testing.T) {
	db := testutil.NewDB(t)
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: t.TempDir(), PublicBaseURL: "http://test"}
	cfg.Limits.Uploads = config.DefaultLimits().Uploads // 30 per hour
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { Mount(r, app.Deps{DB: db, Cfg: cfg}) })
	tok := testutil.Token(t, testutil.NewUser(t, db))
	for i := 1; i <= 6; i++ {
		var body bytes.Buffer
		mw := multipart.NewWriter(&body)
		fw, _ := mw.CreateFormFile("file", "x.jpg")
		fw.Write(testJPEG(t, 16, 16))
		mw.Close()
		req := httptest.NewRequest("POST", "/api/v1/photos", &body)
		req.Header.Set("Content-Type", mw.FormDataContentType())
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		want := 201
		if i == 6 {
			want = 429
		}
		if rec.Code != want {
			t.Fatalf("upload %d: %d, want %d", i, rec.Code, want)
		}
	}
}
