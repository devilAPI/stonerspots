package feed_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestFeedFollowingRequiresLogin(t *testing.T) {
	_, h := setup(t)
	code, _, body := getFeed(t, h, url.Values{"following": {"true"}})
	if code != 401 {
		t.Fatalf("status %d: %s", code, body)
	}
	if code, _, body := getFeed(t, h, url.Values{"following": {"maybe"}}); code != 400 {
		t.Fatalf("bad value: %d %s", code, body)
	}
	if code, _, body := getFeed(t, h, url.Values{"following": {"false"}}); code != 200 {
		t.Fatalf("false: %d %s", code, body)
	}
}

// getFeedAs is getFeed with a logged in caller.
func getFeedAs(t *testing.T, h http.Handler, uid uint64, q url.Values) (*httptest.ResponseRecorder, feedResp) {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/feed?"+q.Encode(), nil)
	req.Header.Set("Authorization", "Bearer "+testutil.Token(t, uid))
	h.ServeHTTP(rec, req)
	var fr feedResp
	if rec.Code == 200 {
		if err := json.Unmarshal(rec.Body.Bytes(), &fr); err != nil {
			t.Fatal(err)
		}
	}
	return rec, fr
}

func TestFeedFollowingShowsOnlyFollowedAuthors(t *testing.T) {
	db, h := setup(t)
	me, alice, bob := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	s1 := newSpot(t, db, bob, 48, 11, 0)
	s2 := newSpot(t, db, bob, 48.1, 11, 0)
	a1 := newUpdate(t, db, s1, alice, "a1", "2026-01-01 10:00:00")
	newUpdate(t, db, s1, bob, "b1", "2026-01-01 11:00:00") // newer, by someone I do not follow
	a2 := newUpdate(t, db, s2, alice, "a2", "2026-01-01 12:00:00")
	hidden := newUpdate(t, db, s2, alice, "hidden", "2026-01-01 13:00:00")
	if _, err := db.Exec(`UPDATE spot_updates SET status = 'hidden' WHERE id = ?`, hidden); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO follows (follower_id, followee_id) VALUES (?, ?)`, me, alice); err != nil {
		t.Fatal(err)
	}

	q := url.Values{"following": {"true"}}
	rec, fr := getFeedAs(t, h, me, q)
	if rec.Code != 200 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	// Every update of the people I follow, newest first, even when someone
	// else posted later on the same spot.
	if len(fr.Items) != 2 || fr.Items[0].ID != a2 || fr.Items[1].ID != a1 {
		t.Fatalf("items: %+v", fr.Items)
	}
	for _, it := range fr.Items {
		if it.Author.ID != alice {
			t.Fatalf("author %d", it.Author.ID)
		}
	}

	// Paging works with the filter.
	q.Set("limit", "1")
	rec, fr = getFeedAs(t, h, me, q)
	if len(fr.Items) != 1 || fr.Items[0].ID != a2 || fr.NextCursor == nil {
		t.Fatalf("page 1: %s", rec.Body)
	}
	q.Set("cursor", *fr.NextCursor)
	rec, fr = getFeedAs(t, h, me, q)
	if len(fr.Items) != 1 || fr.Items[0].ID != a1 || fr.NextCursor != nil {
		t.Fatalf("page 2: %s", rec.Body)
	}

	// Following nobody: empty list, not an error.
	rec, _ = getFeedAs(t, h, bob, url.Values{"following": {"true"}})
	if rec.Code != 200 || rec.Body.String() != `{"items":[],"next_cursor":null}`+"\n" {
		t.Fatalf("bob: %d %q", rec.Code, rec.Body)
	}

	// The normal feed still shows one card per spot, logged in or not.
	_, all, _ := getFeed(t, h, url.Values{})
	if len(all.Items) != 2 {
		t.Fatalf("feed: %+v", all.Items)
	}
}
