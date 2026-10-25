package server_test

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/server"
	"stonerspots/backend/internal/testutil"
)

type e2e struct {
	t     *testing.T
	h     http.Handler
	token string
}

func (c *e2e) do(method, path string, body any) (int, map[string]any, []byte) {
	c.t.Helper()
	var rd *bytes.Reader
	if b, ok := body.([]byte); ok {
		rd = bytes.NewReader(b)
	} else {
		raw, _ := json.Marshal(body)
		rd = bytes.NewReader(raw)
	}
	req := httptest.NewRequest(method, path, rd)
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	rec := httptest.NewRecorder()
	c.h.ServeHTTP(rec, req)
	var m map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &m)
	return rec.Code, m, rec.Body.Bytes()
}

// TestEndToEndFlow runs the real server: register, upload a photo, create a
// spot (which creates its first update), read it back from the feed, like it.
func TestEndToEndFlow(t *testing.T) {
	d := testutil.NewDB(t)
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: t.TempDir(), PublicBaseURL: "http://test", DisablePoW: true}
	c := &e2e{t: t, h: server.New(app.Deps{DB: d, Cfg: cfg})}

	code, reg, raw := c.do("POST", "/api/v1/auth/register", map[string]any{
		"email": "a@example.com", "password": "correct-horse-1", "display_name": "Alice", "adult": true})
	if code != 201 {
		t.Fatalf("register: %d %s", code, raw)
	}
	c.token = reg["access_token"].(string)
	var confirmed *string
	if err := d.QueryRow("SELECT CAST(adult_confirmed_at AS CHAR) FROM users WHERE email='a@example.com'").Scan(&confirmed); err != nil || confirmed == nil {
		t.Fatalf("adult_confirmed_at not stored: %v %v", confirmed, err)
	}

	// upload a photo (multipart)
	var jpg bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 64, 48))
	for x := 0; x < 64; x++ {
		img.Set(x, 5, color.RGBA{0, 200, 0, 255})
	}
	_ = jpeg.Encode(&jpg, img, nil)
	var mp bytes.Buffer
	w := multipart.NewWriter(&mp)
	fw, _ := w.CreateFormFile("file", "a.jpg")
	_, _ = fw.Write(jpg.Bytes())
	_ = w.Close()
	req := httptest.NewRequest("POST", "/api/v1/photos", &mp)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+c.token)
	rec := httptest.NewRecorder()
	c.h.ServeHTTP(rec, req)
	if rec.Code != 201 {
		t.Fatalf("photo: %d %s", rec.Code, rec.Body)
	}
	var ph map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &ph)
	photoID := ph["id"]

	// create spot in Zurich with the photo and description
	code, spot, raw := c.do("POST", "/api/v1/spots", map[string]any{
		"title": "Bench by the lake", "description": "great view",
		"lat": 47.3667, "lon": 8.5400, "photo_ids": []any{photoID}})
	if code != 201 {
		t.Fatalf("create spot: %d %s", code, raw)
	}
	spotID := int(spot["id"].(float64))
	if spot["cover_url"] == "" {
		t.Fatalf("cover_url empty: %v", spot)
	}

	// a second spot 5 m away is flagged as a duplicate with the existing id
	code, dup, _ := c.do("POST", "/api/v1/spots", map[string]any{
		"title": "Same bench", "lat": 47.36674, "lon": 8.5400})
	if code != 409 || int(dup["existing_id"].(float64)) != spotID {
		t.Fatalf("duplicate: %d %v", code, dup)
	}

	// first update shows up in the feed, filtered by spot
	code, feed, raw := c.do("GET", "/api/v1/feed?sort=new&spot_id="+itoa(spotID), nil)
	items, _ := feed["items"].([]any)
	if code != 200 || len(items) != 1 {
		t.Fatalf("feed: %d %s", code, raw)
	}
	if got := len(items[0].(map[string]any)["photos"].([]any)); got != 1 {
		t.Fatalf("photos on first update = %d", got)
	}
	code, other, _ := c.do("GET", "/api/v1/feed?spot_id=999999", nil)
	if code != 200 || len(other["items"].([]any)) != 0 {
		t.Fatalf("spot_id filter leaked: %d %v", code, other)
	}

	// a spot with a bad photo id is rejected and not left behind
	code, _, _ = c.do("POST", "/api/v1/spots", map[string]any{
		"title": "Ghost spot", "lat": 48.2, "lon": 16.37, "photo_ids": []any{99999}})
	if code != 400 {
		t.Fatalf("bad photo: %d", code)
	}
	var n int
	_ = d.QueryRow("SELECT COUNT(*) FROM spots WHERE title='Ghost spot'").Scan(&n)
	if n != 0 {
		t.Fatalf("ghost spot left behind")
	}

	// like, then the spot shows up first in "top"
	code, like, _ := c.do("PUT", "/api/v1/spots/"+itoa(spotID)+"/like", nil)
	if code != 200 || like["like_count"].(float64) != 1 {
		t.Fatalf("like: %d %v", code, like)
	}
	// the map query finds it
	code, _, raw = c.do("GET", "/api/v1/spots?south=47&west=8&north=48&east=9", nil)
	if code != 200 || !bytes.Contains(raw, []byte("Bench by the lake")) {
		t.Fatalf("bbox: %d %s", code, raw)
	}
}

func itoa(i int) string { b, _ := json.Marshal(i); return string(b) }
