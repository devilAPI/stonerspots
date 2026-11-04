package users_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/testutil"
	"stonerspots/backend/internal/users"
)

// Every follow notifies someone, so one account may follow only so many
// users a day; unfollowing is not limited.
func TestFollowsHaveADailyQuota(t *testing.T) {
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	users.Mount(r, app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://test"}},
		quotas.NewTracker(quotas.Config{FollowsPerDay: 2}))
	me := testutil.NewUser(t, db)
	a, b, c := testutil.NewUser(t, db), testutil.NewUser(t, db), testutil.NewUser(t, db)
	for _, id := range []uint64{a, b} {
		if w := do(t, r, "PUT", fmt.Sprintf("/users/%d/follow", id), me); w.Code != 204 {
			t.Fatalf("follow: %d %s", w.Code, w.Body)
		}
	}
	w := do(t, r, "PUT", fmt.Sprintf("/users/%d/follow", c), me)
	if w.Code != 429 || !strings.Contains(w.Body.String(), "quota_exceeded") {
		t.Fatalf("third follow: %d %s", w.Code, w.Body)
	}
	if w := do(t, r, "DELETE", fmt.Sprintf("/users/%d/follow", a), me); w.Code != 204 {
		t.Fatalf("unfollow: %d", w.Code)
	}
	// another user has their own quota
	if w := do(t, r, "PUT", fmt.Sprintf("/users/%d/follow", c), a); w.Code != 204 {
		t.Fatalf("other user: %d", w.Code)
	}
}
