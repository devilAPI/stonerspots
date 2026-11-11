package dataexport_test

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/dataexport"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/testutil"
)

const base = "https://api.beispiel.test"

func mustExec(t *testing.T, d *sql.DB, q string, args ...any) uint64 {
	t.Helper()
	res, err := d.Exec(q, args...)
	if err != nil {
		t.Fatalf("%s: %v", q, err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func router(d *sql.DB, exports ratelimit.Rule) http.Handler {
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: base}
	cfg.Limits.Exports = exports
	r := chi.NewRouter()
	dataexport.Mount(r, app.Deps{DB: d, Cfg: cfg})
	return r
}

func export(t *testing.T, h http.Handler, uid uint64) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/me/export", nil)
	req.Header.Set("Authorization", "Bearer "+testutil.Token(t, uid))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// fixture: me with content of every kind, and other users around me.
type fixture struct {
	me, other, fan                   uint64
	mySpot, otherSpot, hiddenSpot    uint64
	myUpdate, myComment, myReview    uint64
	attachedPhoto, loosePhoto, myRep uint64
}

func setup(t *testing.T, d *sql.DB) fixture {
	var f fixture
	f.me = mustExec(t, d, `INSERT INTO users (email, password_hash, display_name, bio, adult_confirmed_at, email_verified, avatar_key, totp_secret)
		VALUES ('me@beispiel.test', '$2a$12$secret-hash', 'Me', 'Meine Bio', NOW(), 1, 'avatars/me.jpg', 'TOTPSECRET')`)
	f.other = mustExec(t, d, `INSERT INTO users (email, password_hash, display_name) VALUES ('other@beispiel.test', 'x', 'Other')`)
	f.fan = mustExec(t, d, `INSERT INTO users (email, password_hash, display_name) VALUES ('fan@beispiel.test', 'x', 'Fan')`)

	f.mySpot = mustExec(t, d, `INSERT INTO spots (user_id, title, description, location) VALUES (?, 'My bench', 'by the river', POINT(8.5417, 47.3769))`, f.me)
	mustExec(t, d, `INSERT INTO spot_tags (spot_id, tag) VALUES (?, 'view'), (?, 'quiet')`, f.mySpot, f.mySpot)
	f.otherSpot = mustExec(t, d, `INSERT INTO spots (user_id, title, description, location) VALUES (?, 'Their lake', '', POINT(11.6, 48.1))`, f.other)
	f.hiddenSpot = mustExec(t, d, `INSERT INTO spots (user_id, title, description, location, status) VALUES (?, 'Removed spot', '', POINT(11.7, 48.2), 'hidden')`, f.other)

	f.myUpdate = mustExec(t, d, `INSERT INTO spot_updates (spot_id, user_id, body, tag) VALUES (?, ?, 'still nice', 'still_good')`, f.otherSpot, f.me)
	f.attachedPhoto = mustExec(t, d, "INSERT INTO photos (user_id, `key`, thumb_key, width, height, update_id) VALUES (?, 'p/a.jpg', 'p/a_t.jpg', 800, 600, ?)", f.me, f.myUpdate)
	f.loosePhoto = mustExec(t, d, "INSERT INTO photos (user_id, `key`, thumb_key, width, height) VALUES (?, 'p/b.jpg', 'p/b_t.jpg', 10, 20)", f.me)
	mustExec(t, d, "INSERT INTO photos (user_id, `key`, thumb_key, width, height) VALUES (?, 'p/other.jpg', 'p/other_t.jpg', 1, 1)", f.other)
	mustExec(t, d, `INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'not mine')`, f.mySpot, f.other)

	f.myComment = mustExec(t, d, `INSERT INTO comments (spot_id, user_id, body) VALUES (?, ?, 'was there')`, f.hiddenSpot, f.me)
	mustExec(t, d, `INSERT INTO comments (spot_id, user_id, body) VALUES (?, ?, 'other comment')`, f.mySpot, f.other)
	f.myReview = mustExec(t, d, `INSERT INTO spot_reviews (spot_id, user_id, rating, body) VALUES (?, ?, 4, 'good')`, f.otherSpot, f.me)
	mustExec(t, d, `INSERT INTO spot_likes (user_id, spot_id) VALUES (?, ?)`, f.me, f.otherSpot)
	mustExec(t, d, `INSERT INTO spot_likes (user_id, spot_id) VALUES (?, ?)`, f.other, f.mySpot)

	mustExec(t, d, `INSERT INTO follows (follower_id, followee_id) VALUES (?, ?)`, f.me, f.other)
	mustExec(t, d, `INSERT INTO follows (follower_id, followee_id) VALUES (?, ?)`, f.fan, f.me)
	mustExec(t, d, `INSERT INTO follows (follower_id, followee_id) VALUES (?, ?)`, f.fan, f.other)

	list := mustExec(t, d, `INSERT INTO spot_lists (user_id, name, is_default) VALUES (?, 'Saved', 1)`, f.me)
	mustExec(t, d, `INSERT INTO spot_list_items (list_id, spot_id) VALUES (?, ?), (?, ?)`, list, f.otherSpot, list, f.hiddenSpot)
	otherList := mustExec(t, d, `INSERT INTO spot_lists (user_id, name, is_default) VALUES (?, 'Theirs', 1)`, f.other)
	mustExec(t, d, `INSERT INTO spot_list_items (list_id, spot_id) VALUES (?, ?)`, otherList, f.mySpot)

	f.myRep = mustExec(t, d, `INSERT INTO reports (user_id, target_type, target_id, reason) VALUES (?, 'spot', ?, 'spam')`, f.me, f.hiddenSpot)
	mustExec(t, d, `INSERT INTO reports (user_id, target_type, target_id, reason) VALUES (?, 'spot', ?, 'about me')`, f.other, f.mySpot)

	mustExec(t, d, `INSERT INTO activity (user_id, actor_id, kind) VALUES (?, ?, 'follow')`, f.me, f.fan)
	mustExec(t, d, `INSERT INTO activity (user_id, actor_id, kind, spot_id) VALUES (?, ?, 'like', ?)`, f.me, f.other, f.mySpot)
	mustExec(t, d, `INSERT INTO activity (user_id, actor_id, kind) VALUES (?, ?, 'follow')`, f.other, f.me)

	mustExec(t, d, `INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at) VALUES (?, ?, 'fam', ?)`,
		f.me, strings.Repeat("a", 64), time.Now().Add(time.Hour))
	return f
}

func TestExport(t *testing.T) {
	d := testutil.NewDB(t)
	f := setup(t, d)
	rec := export(t, router(d, ratelimit.Rule{}), f.me)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	if got := rec.Header().Get("Content-Disposition"); got != `attachment; filename="stonerspots-export.json"` {
		t.Fatalf("Content-Disposition = %q", got)
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
		t.Fatalf("Content-Type = %q", got)
	}
	raw := rec.Body.String()
	for _, secret := range []string{"secret-hash", "TOTPSECRET", strings.Repeat("a", 64), "other@beispiel.test", "fan@beispiel.test", "not mine", "other comment", "about me", "p/other.jpg"} {
		if strings.Contains(raw, secret) {
			t.Errorf("export contains %q", secret)
		}
	}

	var doc dataexport.Document
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatal(err)
	}
	if doc.Format != dataexport.Format || doc.ExportedAt.IsZero() || len(doc.Notes) == 0 {
		t.Fatalf("header = %q %v %v", doc.Format, doc.ExportedAt, doc.Notes)
	}

	p := doc.Profile
	if p.ID != f.me || p.Email != "me@beispiel.test" || p.DisplayName != "Me" || p.Bio != "Meine Bio" || !p.EmailVerified || p.AdultConfirmedAt == nil || p.CreatedAt.IsZero() {
		t.Fatalf("profile = %+v", p)
	}
	if p.AvatarURL == nil || *p.AvatarURL != base+"/api/v1/media/avatars/me.jpg" {
		t.Fatalf("avatar = %v", p.AvatarURL)
	}

	if len(doc.Spots) != 1 {
		t.Fatalf("spots = %+v", doc.Spots)
	}
	s := doc.Spots[0]
	if s.ID != f.mySpot || s.Title != "My bench" || s.Lat != 47.3769 || s.Lon != 8.5417 || s.Status != "active" ||
		strings.Join(s.Tags, ",") != "quiet,view" {
		t.Fatalf("spot = %+v", s)
	}

	if len(doc.Updates) != 1 || doc.Updates[0].ID != f.myUpdate || doc.Updates[0].Tag != "still_good" ||
		doc.Updates[0].SpotTitle == nil || *doc.Updates[0].SpotTitle != "Their lake" {
		t.Fatalf("updates = %+v", doc.Updates)
	}
	ph := doc.Updates[0].Photos
	if len(ph) != 1 || ph[0].ID != f.attachedPhoto || ph[0].URL != base+"/api/v1/media/p/a.jpg" || ph[0].ThumbURL != base+"/api/v1/media/p/a_t.jpg" {
		t.Fatalf("update photos = %+v", ph)
	}
	if len(doc.Photos) != 1 || doc.Photos[0].ID != f.loosePhoto || doc.Photos[0].Width != 10 {
		t.Fatalf("unattached photos = %+v", doc.Photos)
	}

	// the comment is on a spot hidden by moderation: no title
	if len(doc.Comments) != 1 || doc.Comments[0].ID != f.myComment || doc.Comments[0].Body != "was there" || doc.Comments[0].SpotTitle != nil {
		t.Fatalf("comments = %+v", doc.Comments)
	}
	if len(doc.Reviews) != 1 || doc.Reviews[0].ID != f.myReview || doc.Reviews[0].Rating != 4 {
		t.Fatalf("reviews = %+v", doc.Reviews)
	}
	if len(doc.Likes) != 1 || doc.Likes[0].SpotID != f.otherSpot {
		t.Fatalf("likes = %+v", doc.Likes)
	}

	if len(doc.Following) != 1 || doc.Following[0].UserID != f.other || doc.Following[0].DisplayName != "Other" {
		t.Fatalf("following = %+v", doc.Following)
	}
	if len(doc.Followers) != 1 || doc.Followers[0].UserID != f.fan || doc.Followers[0].DisplayName != "Fan" {
		t.Fatalf("followers = %+v", doc.Followers)
	}

	if len(doc.Lists) != 1 || doc.Lists[0].Name != "Saved" || !doc.Lists[0].IsDefault || len(doc.Lists[0].Spots) != 2 {
		t.Fatalf("lists = %+v", doc.Lists)
	}
	if it := doc.Lists[0].Spots; it[0].SpotID != f.otherSpot || it[0].SpotTitle == nil || it[1].SpotTitle != nil {
		t.Fatalf("list items = %+v", it)
	}

	if len(doc.Reports) != 1 || doc.Reports[0].ID != f.myRep || doc.Reports[0].Reason != "spam" || doc.Reports[0].TargetType != "spot" {
		t.Fatalf("reports = %+v", doc.Reports)
	}

	if len(doc.Activity) != 2 || doc.Activity[0].Kind != "follow" || doc.Activity[0].ActorName != "Fan" ||
		doc.Activity[1].Kind != "like" || doc.Activity[1].SpotID == nil || *doc.Activity[1].SpotID != f.mySpot {
		t.Fatalf("activity = %+v", doc.Activity)
	}
	if len(doc.Sessions) != 1 || doc.Sessions[0].RevokedAt != nil {
		t.Fatalf("sessions = %+v", doc.Sessions)
	}
}

// A new account gets empty lists, not nulls.
func TestExportEmptyAccount(t *testing.T) {
	d := testutil.NewDB(t)
	uid := testutil.NewUser(t, d)
	rec := export(t, router(d, ratelimit.Rule{}), uid)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var doc map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"spots", "updates", "unattached_photos", "comments", "reviews", "likes",
		"following", "followers", "lists", "reports", "activity", "sessions"} {
		if _, ok := doc[k].([]any); !ok {
			t.Errorf("%s = %#v, want []", k, doc[k])
		}
	}
}

func TestExportAuthAndLimit(t *testing.T) {
	d := testutil.NewDB(t)
	uid := testutil.NewUser(t, d)
	other := testutil.NewUser(t, d)
	h := router(d, ratelimit.Rule{N: 3, Per: 24 * time.Hour})

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/me/export", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("no token: status %d", rec.Code)
	}

	for i := 0; i < 3; i++ {
		if rec := export(t, h, uid); rec.Code != http.StatusOK {
			t.Fatalf("export %d: status %d", i, rec.Code)
		}
	}
	rec = export(t, h, uid)
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") == "" {
		t.Fatalf("fourth export: status %d", rec.Code)
	}
	// per user, not global
	if rec := export(t, h, other); rec.Code != http.StatusOK {
		t.Fatalf("other user: status %d", rec.Code)
	}
}

// A token of a deleted account gets 401, not an empty document.
func TestExportDeletedUser(t *testing.T) {
	d := testutil.NewDB(t)
	uid := testutil.NewUser(t, d)
	mustExec(t, d, `DELETE FROM users WHERE id = ?`, uid)
	if rec := export(t, router(d, ratelimit.Rule{}), uid); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d", rec.Code)
	}
}
