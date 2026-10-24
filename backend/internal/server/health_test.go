package server_test

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/db"
	"stonerspots/backend/internal/server"
	"stonerspots/backend/internal/testutil"
)

func TestHealth(t *testing.T) {
	d := testutil.NewDB(t)
	h := server.New(app.Deps{DB: d, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	var got map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got["status"] != "ok" || got["db"] != "ok" {
		t.Fatalf("body = %v", got)
	}
}

func TestMigrationsApplyAndRollBack(t *testing.T) {
	d, dsn := testutil.NewEmptyDB(t)
	dir := testutil.MigrationsDir()

	if err := db.Migrate(dsn, dir); err != nil {
		t.Fatalf("migrate up: %v", err)
	}
	// Idempotent: a second run is a no-op, not an error.
	if err := db.Migrate(dsn, dir); err != nil {
		t.Fatalf("migrate up (second run): %v", err)
	}
	for _, tbl := range []string{"users", "refresh_tokens", "spots", "photos", "spot_updates", "spot_likes", "reports"} {
		if !tableExists(t, d, tbl) {
			t.Errorf("table %s missing after up", tbl)
		}
	}

	// Spatial column: POINT(lon, lat) round-trips with x = lon, y = lat.
	if _, err := d.Exec(`INSERT INTO users (email, password_hash, display_name) VALUES ('a@b.c', 'x', 'A')`); err != nil {
		t.Fatal(err)
	}
	const lat, lon = 47.3769, 8.5417
	if _, err := d.Exec(`INSERT INTO spots (user_id, title, description, category, location)
		VALUES (1, 'Zurich bench', '', 'bench', POINT(?, ?))`, lon, lat); err != nil {
		t.Fatalf("insert spot: %v", err)
	}
	var gotLat, gotLon float64
	if err := d.QueryRow(`SELECT ST_Y(location), ST_X(location) FROM spots WHERE id = 1`).Scan(&gotLat, &gotLon); err != nil {
		t.Fatal(err)
	}
	if gotLat != lat || gotLon != lon {
		t.Fatalf("lat/lon = %v/%v", gotLat, gotLon)
	}
	var status string
	if err := d.QueryRow(`SELECT status FROM spots WHERE id = 1`).Scan(&status); err != nil || status != "active" {
		t.Fatalf("status = %q err=%v", status, err)
	}

	// EXPLAIN must pick the spatial index for an MBRContains bbox query.
	rows, err := d.Query(`EXPLAIN SELECT id FROM spots WHERE MBRContains(
		ENVELOPE(LINESTRING(POINT(8, 47), POINT(9, 48))), location)`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	cols, _ := rows.Columns()
	var key string
	for rows.Next() {
		vals := make([]sql.NullString, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			t.Fatal(err)
		}
		for i, c := range cols {
			if c == "key" {
				key = vals[i].String
			}
		}
	}
	if key != "idx_spots_location" {
		t.Fatalf("EXPLAIN key = %q, want idx_spots_location", key)
	}

	// Roll back every migration.
	if err := db.MigrateDown(dsn, dir); err != nil {
		t.Fatalf("migrate down: %v", err)
	}
	for _, tbl := range []string{"users", "refresh_tokens", "spots", "photos", "spot_updates", "spot_likes", "reports"} {
		if tableExists(t, d, tbl) {
			t.Errorf("table %s still exists after down", tbl)
		}
	}
	// And forward again.
	if err := db.Migrate(dsn, dir); err != nil {
		t.Fatalf("migrate up after down: %v", err)
	}
}

func tableExists(t *testing.T, d *sql.DB, name string) bool {
	t.Helper()
	var n int
	err := d.QueryRow(`SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?`, name).Scan(&n)
	if err != nil {
		t.Fatal(err)
	}
	return n == 1
}
