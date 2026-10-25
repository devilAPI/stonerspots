package feed_test

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/testutil"
)

func setupDir(t *testing.T) (*sql.DB, http.Handler, string) {
	t.Helper()
	db := testutil.NewDB(t)
	dir := t.TempDir()
	r := chi.NewRouter()
	feed.Mount(r, app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://test", UploadDir: dir}}, quotas.NewTracker(quotas.Config{}))
	return db, r, dir
}

func call(t *testing.T, h http.Handler, method, path string, uid uint64, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if uid != 0 {
		req.Header.Set("Authorization", "Bearer "+testutil.Token(t, uid))
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

type item struct {
	ID       uint64  `json:"id"`
	Body     string  `json:"body"`
	Tag      string  `json:"tag"`
	EditedAt *string `json:"edited_at"`
	Photos   []struct {
		ID uint64 `json:"id"`
	} `json:"photos"`
	Spot struct {
		RatingAvg   float64 `json:"rating_avg"`
		RatingCount int     `json:"rating_count"`
	} `json:"spot"`
}

func decode(t *testing.T, rec *httptest.ResponseRecorder) item {
	t.Helper()
	var it item
	if err := json.Unmarshal(rec.Body.Bytes(), &it); err != nil {
		t.Fatal(err)
	}
	return it
}

func getFeedRaw(t *testing.T, h http.Handler) (int, []item, string) {
	t.Helper()
	rec := call(t, h, "GET", "/feed", 0, "")
	var out struct {
		Items []item `json:"items"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out.Items, rec.Body.String()
}

func TestUpdateTagDefaultAndValidation(t *testing.T) {
	db, h, _ := setupDir(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	path := fmt.Sprintf("/spots/%d/updates", s)
	rec := call(t, h, "POST", path, u, `{"body":"hi"}`)
	if it := decode(t, rec); rec.Code != 201 || it.Tag != "note" || it.EditedAt != nil {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"edited_at":null`)) {
		t.Fatalf("edited_at must be present: %s", rec.Body)
	}
	for _, tag := range []string{"note", "still_good", "crowded", "dirty", "closed"} {
		rec := call(t, h, "POST", path, u, fmt.Sprintf(`{"body":"x","tag":%q}`, tag))
		if it := decode(t, rec); rec.Code != 201 || it.Tag != tag {
			t.Fatalf("%s: %d %s", tag, rec.Code, rec.Body)
		}
	}
	rec = call(t, h, "POST", path, u, `{"body":"x","tag":"bogus"}`)
	if rec.Code != 400 || !strings.Contains(rec.Body.String(), "invalid_tag") {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	_, items, _ := getFeedRaw(t, h)
	if len(items) == 0 || items[0].Tag == "" {
		t.Fatalf("feed lacks tag: %+v", items)
	}
}

func TestFeedSpotRatings(t *testing.T) {
	db, h, _ := setupDir(t)
	u, r1, r2 := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	newUpdate(t, db, s, u, "a", "2026-01-01 10:00:00")
	db.Exec(`INSERT INTO spot_reviews (spot_id,user_id,rating,body) VALUES (?,?,5,''),(?,?,4,'')`, s, r1, s, r2)
	_, items, body := getFeedRaw(t, h)
	if len(items) != 1 || items[0].Spot.RatingCount != 2 || items[0].Spot.RatingAvg != 4.5 {
		t.Fatalf("%s", body)
	}
}

func TestPatchUpdate(t *testing.T) {
	db, h, _ := setupDir(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	id := newUpdate(t, db, s, u, "orig", "2026-01-01 10:00:00")
	path := fmt.Sprintf("/updates/%d", id)

	if rec := call(t, h, "PATCH", path, 0, `{"body":"x"}`); rec.Code != 401 {
		t.Fatalf("anon %d", rec.Code)
	}
	if rec := call(t, h, "PATCH", path, other, `{"body":"x"}`); rec.Code != 403 || !strings.Contains(rec.Body.String(), "forbidden") {
		t.Fatalf("other %d %s", rec.Code, rec.Body)
	}
	if rec := call(t, h, "PATCH", "/updates/99999", u, `{"body":"x"}`); rec.Code != 404 {
		t.Fatalf("missing %d", rec.Code)
	}
	if rec := call(t, h, "PATCH", path, u, `null`); rec.Code != 400 || !strings.Contains(rec.Body.String(), "invalid_body") {
		t.Fatalf("null %d %s", rec.Code, rec.Body)
	}
	if rec := call(t, h, "PATCH", path, u, `{}`); rec.Code != 400 || !strings.Contains(rec.Body.String(), "empty_patch") {
		t.Fatalf("empty %d %s", rec.Code, rec.Body)
	}
	if rec := call(t, h, "PATCH", path, u, `{"tag":"nope"}`); rec.Code != 400 || !strings.Contains(rec.Body.String(), "invalid_tag") {
		t.Fatalf("tag %d %s", rec.Code, rec.Body)
	}
	if rec := call(t, h, "PATCH", path, u, `{"body":"   "}`); rec.Code != 400 || !strings.Contains(rec.Body.String(), "invalid_body") {
		t.Fatalf("blank without photo %d %s", rec.Code, rec.Body)
	}
	if rec := call(t, h, "PATCH", path, u, fmt.Sprintf(`{"body":%q}`, strings.Repeat("a", 2001))); rec.Code != 400 {
		t.Fatalf("long %d", rec.Code)
	}
	var edited sql.NullTime
	db.QueryRow(`SELECT edited_at FROM spot_updates WHERE id=?`, id).Scan(&edited)
	if edited.Valid {
		t.Fatal("failed patches must not set edited_at")
	}

	rec := call(t, h, "PATCH", path, u, `{"body":" new text ","tag":"crowded"}`)
	it := decode(t, rec)
	if rec.Code != 200 || it.Body != "new text" || it.Tag != "crowded" || it.EditedAt == nil || it.ID != id {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	rec = call(t, h, "PATCH", path, u, `{"tag":"closed"}`)
	if it := decode(t, rec); rec.Code != 200 || it.Body != "new text" || it.Tag != "closed" {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	p := newPhoto(t, db, u)
	db.Exec(`UPDATE photos SET update_id=? WHERE id=?`, id, p)
	rec = call(t, h, "PATCH", path, u, `{"body":""}`)
	if it := decode(t, rec); rec.Code != 200 || it.Body != "" || len(it.Photos) != 1 {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	db.Exec(`UPDATE spot_updates SET status='hidden' WHERE id=?`, id)
	if rec := call(t, h, "PATCH", path, u, `{"body":"x"}`); rec.Code != 404 {
		t.Fatalf("hidden %d", rec.Code)
	}
}

func TestDeleteUpdate(t *testing.T) {
	db, h, dir := setupDir(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	id := newUpdate(t, db, s, u, "orig", "2026-01-01 10:00:00")
	keep := newUpdate(t, db, s, u, "keep", "2026-01-02 10:00:00")
	os.MkdirAll(filepath.Join(dir, "a"), 0o755)
	for _, f := range []string{"a/p.jpg", "a/t.jpg", "a/keep.jpg", "a/keept.jpg"} {
		os.WriteFile(filepath.Join(dir, f), []byte("x"), 0o644)
	}
	db.Exec("INSERT INTO photos (user_id,`key`,thumb_key,width,height,update_id) VALUES (?,?,?,1,1,?)", u, "a/p.jpg", "a/t.jpg", id)
	db.Exec("INSERT INTO photos (user_id,`key`,thumb_key,width,height,update_id) VALUES (?,?,?,1,1,?)", u, "a/keep.jpg", "a/keept.jpg", keep)
	db.Exec("INSERT INTO photos (user_id,`key`,thumb_key,width,height,update_id) VALUES (?,?,?,1,1,?)", u, "../evil.jpg", "/abs.jpg", id)
	db.Exec(`INSERT INTO reports (user_id,target_type,target_id) VALUES (?, 'update', ?), (?, 'update', ?)`, other, id, other, keep)
	path := fmt.Sprintf("/updates/%d", id)

	if rec := call(t, h, "DELETE", path, 0, ""); rec.Code != 401 {
		t.Fatalf("anon %d", rec.Code)
	}
	if rec := call(t, h, "DELETE", path, other, ""); rec.Code != 403 {
		t.Fatalf("other %d", rec.Code)
	}
	if rec := call(t, h, "DELETE", "/updates/99999", u, ""); rec.Code != 404 {
		t.Fatalf("missing %d", rec.Code)
	}
	if rec := call(t, h, "DELETE", path, u, ""); rec.Code != 204 {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	var n int
	db.QueryRow(`SELECT COUNT(*) FROM spot_updates WHERE id=?`, id).Scan(&n)
	if n != 0 {
		t.Fatal("update remains")
	}
	db.QueryRow(`SELECT COUNT(*) FROM photos`).Scan(&n)
	if n != 1 {
		t.Fatalf("photo rows left: %d (want only the other update's)", n)
	}
	db.QueryRow(`SELECT COUNT(*) FROM reports WHERE target_type='update'`).Scan(&n)
	if n != 1 {
		t.Fatalf("reports %d", n)
	}
	for _, f := range []string{"a/p.jpg", "a/t.jpg"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err == nil {
			t.Fatalf("%s not removed", f)
		}
	}
	for _, f := range []string{"a/keep.jpg", "a/keept.jpg"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Fatalf("%s wrongly removed", f)
		}
	}
	if rec := call(t, h, "DELETE", path, u, ""); rec.Code != 404 {
		t.Fatalf("again %d", rec.Code)
	}
}
