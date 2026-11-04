package server_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/server"
	"stonerspots/backend/internal/testutil"
)

// GET /legal goes through the whole middleware chain without a login and
// may be cached, unlike every other API answer (no-store).
func TestLegalRoute(t *testing.T) {
	d := testutil.NewDB(t)
	h := server.New(app.Deps{DB: d, Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret),
		Legal: config.LegalConfig{
			OperatorName: "Erika Beispiel",
			Address:      "c/o Adressdienst\nWeg 2\n10115 Berlin",
			Email:        "erika@beispiel.test",
		},
	}})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/legal", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	if got := rec.Header().Get("Cache-Control"); got != "public, max-age=3600" {
		t.Fatalf("Cache-Control = %q", got)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["configured"] != true || body["operator_name"] != "Erika Beispiel" {
		t.Fatalf("body = %v", body)
	}
}

func TestExportNeedsLogin(t *testing.T) {
	d := testutil.NewDB(t)
	h := server.New(app.Deps{DB: d, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/me/export", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
