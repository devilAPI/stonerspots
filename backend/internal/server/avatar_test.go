package server_test

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/server"
	"stonerspots/backend/internal/testutil"
)

const avatarMedia = "http://test/api/v1/media/"

// itemsOf returns the items of a list response: a bare array or {"items": [...]}.
func itemsOf(t *testing.T, raw []byte) []map[string]any {
	t.Helper()
	var arr []map[string]any
	if json.Unmarshal(raw, &arr) == nil {
		return arr
	}
	var obj struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(raw, &obj); err != nil {
		t.Fatalf("not a list response: %s", raw)
	}
	return obj.Items
}

// wantUser checks that v is a user object {id, display_name, avatar_url}
// with the given id and avatar_url (nil: JSON null, but the key present).
func wantUser(t *testing.T, where string, v any, id float64, avatar *string) {
	t.Helper()
	m, ok := v.(map[string]any)
	if !ok {
		t.Fatalf("%s: user object is %T %v", where, v, v)
	}
	if m["id"] != id {
		t.Fatalf("%s: id = %v, want %v", where, m["id"], id)
	}
	if _, ok := m["display_name"].(string); !ok {
		t.Fatalf("%s: display_name missing: %v", where, m)
	}
	got, present := m["avatar_url"]
	if !present {
		t.Fatalf("%s: avatar_url missing: %v", where, m)
	}
	if avatar == nil {
		if got != nil {
			t.Fatalf("%s: avatar_url = %v, want null", where, got)
		}
		return
	}
	if got != *avatar {
		t.Fatalf("%s: avatar_url = %v, want %q", where, got, *avatar)
	}
}

func jpegFile(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		img.Set(x, h/2, color.RGBA{0, 200, 0, 255})
	}
	var b bytes.Buffer
	_ = jpeg.Encode(&b, img, nil)
	return b.Bytes()
}

// uploadAvatar PUTs data as multipart "photo" to path and returns the
// status and the avatar_url of the answer.
func (c *e2e) uploadAvatar(path string, data []byte) (int, string) {
	c.t.Helper()
	var mp bytes.Buffer
	w := multipart.NewWriter(&mp)
	fw, _ := w.CreateFormFile("photo", "me.jpg")
	_, _ = fw.Write(data)
	_ = w.Close()
	req := httptest.NewRequest("PUT", path, &mp)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+c.token)
	rec := httptest.NewRecorder()
	c.h.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	u, _ := out["avatar_url"].(string)
	return rec.Code, u
}

func (c *e2e) putAvatar(data []byte) string {
	c.t.Helper()
	code, u := c.uploadAvatar("/api/v1/me/avatar", data)
	if code != 200 {
		c.t.Fatalf("PUT /me/avatar: %d", code)
	}
	if !strings.HasPrefix(u, avatarMedia+"avatars/") {
		c.t.Fatalf("avatar_url = %v", u)
	}
	return u
}

func (c *e2e) as(token string) *e2e { return &e2e{t: c.t, h: c.h, token: token} }

func register(t *testing.T, c *e2e, email, name string) (token string, user map[string]any) {
	t.Helper()
	code, reg, raw := c.as("").do("POST", "/api/v1/auth/register", map[string]any{
		"email": email, "password": "correct-horse-1", "display_name": name, "adult": true})
	if code != 201 {
		t.Fatalf("register %s: %d %s", name, code, raw)
	}
	return reg["access_token"].(string), reg["user"].(map[string]any)
}

// TestAvatarURLEverywhere checks avatar_url on every user object and the
// author on every spot list, through the real router.
func TestAvatarURLEverywhere(t *testing.T) {
	d := testutil.NewDB(t)
	uploads := t.TempDir()
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: uploads, PublicBaseURL: "http://test", DisablePoW: true}
	c := &e2e{t: t, h: server.New(app.Deps{DB: d, Cfg: cfg})}

	aliceTok, aliceUser := register(t, c, "alice@example.com", "Alice")
	wantUser(t, "register user", aliceUser, aliceUser["id"].(float64), nil)
	aliceID := aliceUser["id"].(float64)
	bobTok, bobUser := register(t, c, "bob@example.com", "Bob")
	bobID := bobUser["id"].(float64)
	alice, bob := c.as(aliceTok), c.as(bobTok)

	url := alice.putAvatar(jpegFile(500, 300))

	// GET /me, login and refresh
	_, me, _ := alice.do("GET", "/api/v1/me", nil)
	wantUser(t, "GET /me", me, aliceID, &url)
	code, login, raw := c.as("").do("POST", "/api/v1/auth/login", map[string]any{"login": "alice@example.com", "password": "correct-horse-1"})
	if code != 200 {
		t.Fatalf("login: %d %s", code, raw)
	}
	wantUser(t, "login user", login["user"], aliceID, &url)
	code, ref, raw := c.as("").do("POST", "/api/v1/auth/refresh", map[string]any{"refresh_token": login["refresh_token"]})
	if code != 200 {
		t.Fatalf("refresh: %d %s", code, raw)
	}
	wantUser(t, "refresh user", ref["user"], aliceID, &url)

	// spots: Alice's (with avatar) and Bob's (without)
	code, sa, raw := alice.do("POST", "/api/v1/spots", map[string]any{"title": "Alice Bank", "description": "d", "lat": 47.3667, "lon": 8.54})
	if code != 201 {
		t.Fatalf("spot: %d %s", code, raw)
	}
	aliceSpot := itoa(int(sa["id"].(float64)))
	code, sb, raw := bob.do("POST", "/api/v1/spots", map[string]any{"title": "Bob Wiese", "description": "d", "lat": 47.40, "lon": 8.60})
	if code != 201 {
		t.Fatalf("spot: %d %s", code, raw)
	}
	bobSpot := itoa(int(sb["id"].(float64)))

	_, got, _ := bob.do("GET", "/api/v1/spots/"+aliceSpot, nil)
	wantUser(t, "GET /spots/{id} author", got["author"], aliceID, &url)

	byTitle := func(where string, items []map[string]any) {
		t.Helper()
		seen := 0
		for _, it := range items {
			switch it["title"] {
			case "Alice Bank":
				wantUser(t, where+" (Alice's spot)", it["author"], aliceID, &url)
				seen++
			case "Bob Wiese":
				wantUser(t, where+" (Bob's spot)", it["author"], bobID, nil)
				seen++
			}
		}
		if seen == 0 {
			t.Fatalf("%s: no spot in the response", where)
		}
	}
	for _, path := range []string{
		"/api/v1/spots?south=47&west=8&north=48&east=9",
		"/api/v1/spots/nearby?lat=47.37&lon=8.55&radius_m=20000",
		"/api/v1/spots/search?q=Bank",
		"/api/v1/spots/search?q=Wiese&lat=47.4&lon=8.6",
		"/api/v1/users/" + itoa(int(aliceID)) + "/spots",
		"/api/v1/users/" + itoa(int(bobID)) + "/spots",
	} {
		code, _, raw := bob.do("GET", path, nil)
		if code != 200 {
			t.Fatalf("GET %s: %d %s", path, code, raw)
		}
		byTitle("GET "+path, itemsOf(t, raw))
	}
	if code, _, raw := bob.do("PUT", "/api/v1/lists/default/spots/"+aliceSpot, nil); code != 200 {
		t.Fatalf("save to list: %d %s", code, raw)
	}
	_, _, raw = bob.do("GET", "/api/v1/lists", nil)
	listID := itoa(int(itemsOf(t, raw)[0]["id"].(float64)))
	code, _, raw = bob.do("GET", "/api/v1/lists/"+listID+"/spots", nil)
	if code != 200 {
		t.Fatalf("list spots: %d %s", code, raw)
	}
	byTitle("GET /lists/{id}/spots", itemsOf(t, raw))

	// feed and the spot timeline
	for _, path := range []string{"/api/v1/feed?sort=new", "/api/v1/feed?spot_id=" + aliceSpot, "/api/v1/users/" + itoa(int(aliceID)) + "/updates"} {
		code, _, raw := bob.do("GET", path, nil)
		items := itemsOf(t, raw)
		if code != 200 || len(items) == 0 {
			t.Fatalf("GET %s: %d %s", path, code, raw)
		}
		for _, it := range items {
			if it["author"].(map[string]any)["id"] == aliceID {
				wantUser(t, "GET "+path, it["author"], aliceID, &url)
			} else {
				wantUser(t, "GET "+path, it["author"], bobID, nil)
			}
		}
	}

	// review by Alice on Bob's spot
	code, rv, raw := alice.do("PUT", "/api/v1/spots/"+bobSpot+"/review", map[string]any{"rating": 4, "body": "nice"})
	if code != 200 {
		t.Fatalf("review: %d %s", code, raw)
	}
	wantUser(t, "PUT review", rv["author"], aliceID, &url)
	_, rvs, raw := bob.do("GET", "/api/v1/spots/"+bobSpot+"/reviews", nil)
	items := itemsOf(t, raw)
	if len(items) != 1 {
		t.Fatalf("reviews: %s", raw)
	}
	wantUser(t, "GET reviews", items[0]["author"], aliceID, &url)
	if rvs["mine"] != nil {
		t.Fatalf("Bob has no review: %v", rvs["mine"])
	}
	_, rvs, _ = alice.do("GET", "/api/v1/spots/"+bobSpot+"/reviews", nil)
	wantUser(t, "GET reviews mine", rvs["mine"].(map[string]any)["author"], aliceID, &url)

	// comment by Alice under Bob's first update
	_, _, raw = bob.do("GET", "/api/v1/feed?spot_id="+bobSpot, nil)
	updateID := itoa(int(itemsOf(t, raw)[0]["id"].(float64)))
	code, cm, raw := alice.do("POST", "/api/v1/updates/"+updateID+"/comments", map[string]any{"body": "hi"})
	if code != 201 && code != 200 {
		t.Fatalf("comment: %d %s", code, raw)
	}
	wantUser(t, "POST comment", cm["author"], aliceID, &url)
	_, _, raw = bob.do("GET", "/api/v1/updates/"+updateID+"/comments", nil)
	wantUser(t, "GET comments", itemsOf(t, raw)[0]["author"], aliceID, &url)

	// Bob's activity: Alice reviewed and commented
	_, _, raw = bob.do("GET", "/api/v1/me/activity", nil)
	acts := itemsOf(t, raw)
	if len(acts) < 2 {
		t.Fatalf("activity: %s", raw)
	}
	for _, a := range acts {
		wantUser(t, "activity actor", a["actor"], aliceID, &url)
	}

	// profiles
	_, pa, _ := bob.do("GET", "/api/v1/users/"+itoa(int(aliceID)), nil)
	wantUser(t, "GET /users/{alice}", pa, aliceID, &url)
	_, pb, _ := alice.do("GET", "/api/v1/users/"+itoa(int(bobID)), nil)
	wantUser(t, "GET /users/{bob}", pb, bobID, nil)

	// admin: user list, moderation removal
	if _, err := d.Exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, bobID); err != nil {
		t.Fatal(err)
	}
	_, _, raw = bob.do("GET", "/api/v1/admin/users", nil)
	for _, u := range itemsOf(t, raw) {
		if u["id"] == aliceID {
			wantUser(t, "admin users", u, aliceID, &url)
		}
	}
	if code, _, _ := alice.do("DELETE", "/api/v1/admin/users/"+itoa(int(bobID))+"/avatar", nil); code != 403 {
		t.Fatalf("non-admin moderation: %d", code)
	}
	if code, _, _ := bob.do("DELETE", "/api/v1/admin/users/999999/avatar", nil); code != 404 {
		t.Fatalf("unknown user: %d", code)
	}
	file := filepath.Join(uploads, filepath.FromSlash(strings.TrimPrefix(url, avatarMedia)))
	if _, err := os.Stat(file); err != nil {
		t.Fatalf("avatar file: %v", err)
	}
	for i := 0; i < 2; i++ {
		if code, _, raw := bob.do("DELETE", "/api/v1/admin/users/"+itoa(int(aliceID))+"/avatar", nil); code != 204 {
			t.Fatalf("admin delete avatar #%d: %d %s", i+1, code, raw)
		}
	}
	if _, err := os.Stat(file); !os.IsNotExist(err) {
		t.Fatalf("avatar file after moderation: %v", err)
	}
	_, me, _ = alice.do("GET", "/api/v1/me", nil)
	wantUser(t, "GET /me after moderation", me, aliceID, nil)
	_, got, _ = bob.do("GET", "/api/v1/spots/"+aliceSpot, nil)
	wantUser(t, "spot author after moderation", got["author"], aliceID, nil)

	// an admin can set someone else's avatar; the old file goes
	own := alice.putAvatar(jpegFile(120, 80))
	ownFile := filepath.Join(uploads, filepath.FromSlash(strings.TrimPrefix(own, avatarMedia)))
	if code, _ := alice.uploadAvatar("/api/v1/admin/users/"+itoa(int(bobID))+"/avatar", jpegFile(50, 50)); code != 403 {
		t.Fatalf("non-admin sets avatar: %d", code)
	}
	if code, _ := bob.uploadAvatar("/api/v1/admin/users/999999/avatar", jpegFile(50, 50)); code != 404 {
		t.Fatalf("admin sets avatar of unknown user: %d", code)
	}
	code, set := bob.uploadAvatar("/api/v1/admin/users/"+itoa(int(aliceID))+"/avatar", jpegFile(90, 160))
	if code != 200 || !strings.HasPrefix(set, avatarMedia+"avatars/") || set == own {
		t.Fatalf("admin sets avatar: %d %q", code, set)
	}
	if _, err := os.Stat(ownFile); !os.IsNotExist(err) {
		t.Fatalf("old avatar file after admin replace: %v", err)
	}
	_, me, _ = alice.do("GET", "/api/v1/me", nil)
	wantUser(t, "GET /me after admin replace", me, aliceID, &set)

	// deleting the account removes the avatar file
	url = alice.putAvatar(jpegFile(200, 200))
	file = filepath.Join(uploads, filepath.FromSlash(strings.TrimPrefix(url, avatarMedia)))
	if code, _, raw := alice.do("POST", "/api/v1/me/delete", map[string]any{"password": "correct-horse-1"}); code != 204 {
		t.Fatalf("delete account: %d %s", code, raw)
	}
	if _, err := os.Stat(file); !os.IsNotExist(err) {
		t.Fatalf("avatar file after account deletion: %v", err)
	}
}

// TestSpotAuthorNullWhenOwnerGone: a spot whose account row is gone lists
// with author null (GET /spots/{id} and the lists alike).
func TestSpotAuthorNullWhenOwnerGone(t *testing.T) {
	d := testutil.NewDB(t)
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: t.TempDir(), PublicBaseURL: "http://test", DisablePoW: true}
	c := &e2e{t: t, h: server.New(app.Deps{DB: d, Cfg: cfg})}
	uid := testutil.NewUser(t, d)
	c.token = testutil.Token(t, uid)
	code, s, raw := c.do("POST", "/api/v1/spots", map[string]any{"title": "Orphan", "lat": 47.3667, "lon": 8.54})
	if code != 201 {
		t.Fatalf("spot: %d %s", code, raw)
	}
	id := itoa(int(s["id"].(float64)))
	// The FK cascades on account deletion, so fake a dangling owner.
	ctx := context.Background()
	conn, err := d.Conn(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := conn.ExecContext(ctx, `SET FOREIGN_KEY_CHECKS = 0`); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.ExecContext(ctx, `UPDATE spots SET user_id = 999999 WHERE id = ?`, id); err != nil {
		t.Fatal(err)
	}
	conn.ExecContext(ctx, `SET FOREIGN_KEY_CHECKS = 1`)
	conn.Close()

	code, got, raw := c.do("GET", "/api/v1/spots/"+id, nil)
	if code != 200 {
		t.Fatalf("GET spot: %d %s", code, raw)
	}
	if v, ok := got["author"]; !ok || v != nil {
		t.Fatalf("author = %v (present %v), want null", v, ok)
	}
	_, _, raw = c.do("GET", "/api/v1/spots?south=47&west=8&north=48&east=9", nil)
	items := itemsOf(t, raw)
	if len(items) != 1 {
		t.Fatalf("bbox: %s", raw)
	}
	if v, ok := items[0]["author"]; !ok || v != nil {
		t.Fatalf("bbox author = %v (present %v), want null", v, ok)
	}
}
