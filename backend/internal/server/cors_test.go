package server_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/server"
)

const pagesOrigin = "https://devilapi.github.io"

func corsHandler() http.Handler {
	// no DB: these requests never reach a handler that needs one
	return server.New(app.Deps{Cfg: config.Config{AllowedOrigins: []string{pagesOrigin}}})
}

func TestCORSPreflightAllowedOrigin(t *testing.T) {
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/feed", nil)
	req.Header.Set("Origin", pagesOrigin)
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	req.Header.Set("Access-Control-Request-Headers", "authorization,content-type")
	rec := httptest.NewRecorder()
	corsHandler().ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d", rec.Code)
	}
	h := rec.Header()
	if got := h.Get("Access-Control-Allow-Origin"); got != pagesOrigin {
		t.Fatalf("allow-origin = %q", got)
	}
	if h.Get("Access-Control-Allow-Methods") == "" || h.Get("Access-Control-Allow-Headers") == "" {
		t.Fatalf("missing allow-methods/headers: %v", h)
	}
}

func TestCORSUnknownOriginGetsNoHeaders(t *testing.T) {
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/feed", nil)
	req.Header.Set("Origin", "https://evil.example")
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	rec := httptest.NewRecorder()
	corsHandler().ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("allow-origin = %q, want none", got)
	}
}

func TestCORSSimpleRequestAllowedOrigin(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/does-not-exist", nil)
	req.Header.Set("Origin", pagesOrigin)
	rec := httptest.NewRecorder()
	corsHandler().ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != pagesOrigin {
		t.Fatalf("allow-origin = %q", got)
	}
	if got := rec.Header().Get("Vary"); got != "Origin" {
		t.Fatalf("vary = %q", got)
	}
}
