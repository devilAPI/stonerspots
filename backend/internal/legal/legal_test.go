package legal_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/legal"
	"stonerspots/backend/internal/ratelimit"
)

func get(t *testing.T, h http.Handler) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/legal", nil)
	req.RemoteAddr = "203.0.113.7:1234"
	h.ServeHTTP(rec, req)
	var body map[string]any
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("body %s: %v", rec.Body, err)
		}
	}
	return rec, body
}

func router(cfg config.Config) http.Handler {
	r := chi.NewRouter()
	legal.Mount(r, app.Deps{Cfg: cfg})
	return r
}

func TestLegalConfigured(t *testing.T) {
	h := router(config.Config{Legal: config.LegalConfig{
		OperatorName: "Erika Beispiel",
		Address:      "c/o Adressdienst\nWeg 2\n10115 Berlin",
		Email:        "erika@beispiel.test",
		Country:      "Deutschland",
	}})
	rec, body := get(t, h)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "public, max-age=3600" {
		t.Fatalf("Cache-Control = %q", got)
	}
	want := map[string]any{
		"configured":            true,
		"operator_name":         "Erika Beispiel",
		"address":               "c/o Adressdienst\nWeg 2\n10115 Berlin",
		"email":                 "erika@beispiel.test",
		"phone":                 "",
		"responsible_person":    "Erika Beispiel", // defaults to the operator
		"country":               "Deutschland",
		"privacy_contact_email": "erika@beispiel.test", // defaults to email
		"extra":                 "",
	}
	for k, v := range want {
		if body[k] != v {
			t.Errorf("%s = %#v, want %#v", k, body[k], v)
		}
	}
	if len(body) != len(want) {
		t.Errorf("fields = %v", body)
	}
}

func TestLegalNotConfigured(t *testing.T) {
	for name, l := range map[string]config.LegalConfig{
		"empty":          {},
		"no address":     {OperatorName: "A", Email: "a@beispiel.test"},
		"example values": {OperatorName: "Max Mustermann", Address: "Musterstraße 1", Email: "kontakt@example.org"},
	} {
		t.Run(name, func(t *testing.T) {
			rec, body := get(t, router(config.Config{Legal: l}))
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d", rec.Code)
			}
			if body["configured"] != false {
				t.Fatalf("configured = %v", body["configured"])
			}
			// nothing half-filled or made up is shown
			for _, k := range []string{"operator_name", "address", "email", "responsible_person", "privacy_contact_email"} {
				if body[k] != "" {
					t.Errorf("%s = %q, want empty", k, body[k])
				}
			}
		})
	}
}

func TestLegalRateLimited(t *testing.T) {
	cfg := config.Config{}
	cfg.Limits.Search = ratelimit.Rule{N: 2, Per: time.Minute}
	h := router(cfg)
	for i := 0; i < 2; i++ {
		if rec, _ := get(t, h); rec.Code != http.StatusOK {
			t.Fatalf("request %d: status %d", i, rec.Code)
		}
	}
	if rec, _ := get(t, h); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("third request: status %d, want 429", rec.Code)
	}
}
