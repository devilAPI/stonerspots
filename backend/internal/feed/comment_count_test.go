package feed_test

import (
	"encoding/json"
	"fmt"
	"net/url"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestUpdatesCarryCommentCount(t *testing.T) {
	db, h := setup(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	older := newUpdate(t, db, s, u, "older", "2026-01-01 10:00:00")
	latest := newUpdate(t, db, s, u, "latest", "2026-01-02 10:00:00")
	for _, c := range []struct {
		update, user uint64
		status       string
	}{{latest, u, "active"}, {latest, other, "active"}, {latest, other, "hidden"}, {older, other, "active"}} {
		if _, err := db.Exec(`INSERT INTO comments (update_id, user_id, body, status) VALUES (?, ?, 'c', ?)`,
			c.update, c.user, c.status); err != nil {
			t.Fatal(err)
		}
	}
	counts := func(q url.Values) map[uint64]int {
		t.Helper()
		code, _, body := getFeed(t, h, q)
		if code != 200 {
			t.Fatalf("%d %s", code, body)
		}
		var out struct {
			Items []struct {
				ID           uint64 `json:"id"`
				CommentCount *int   `json:"comment_count"`
			} `json:"items"`
		}
		if err := json.Unmarshal([]byte(body), &out); err != nil {
			t.Fatal(err)
		}
		m := map[uint64]int{}
		for _, it := range out.Items {
			if it.CommentCount == nil {
				t.Fatalf("comment_count missing: %s", body)
			}
			m[it.ID] = *it.CommentCount
		}
		return m
	}
	// the feed (one card per spot): hidden comments do not count
	if m := counts(url.Values{}); len(m) != 1 || m[latest] != 2 {
		t.Fatalf("feed: %v", m)
	}
	// a spot's timeline
	if m := counts(url.Values{"spot_id": {fmt.Sprint(s)}}); m[latest] != 2 || m[older] != 1 {
		t.Fatalf("spot timeline: %v", m)
	}
}
