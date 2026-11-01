package server_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/server"
	"stonerspots/backend/internal/testutil"
)

// 0019 can be rolled back and applied again.
func TestSpotListsMigrationRollsBack(t *testing.T) {
	d, dsn := testutil.NewEmptyDB(t)
	migrateTo(t, dsn, 19)
	migrateTo(t, dsn, 18)
	var n int
	if err := d.QueryRow(`SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = DATABASE() AND table_name IN ('spot_lists', 'spot_list_items')`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("tables left: %d", n)
	}
	migrateTo(t, dsn, 19)
}

func TestListRoutesAreMounted(t *testing.T) {
	d := testutil.NewDB(t)
	h := server.New(app.Deps{DB: d, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}})
	for _, path := range []string{"/api/v1/lists", "/api/v1/spots/1/lists"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s: %d", path, rec.Code)
		}
	}
}
