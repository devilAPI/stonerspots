package auth_test

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"stonerspots/backend/internal/auth"
)

var secret = []byte("unit-test-secret")

func probe(t *testing.T, mw func(http.Handler) http.Handler, header string) (*httptest.ResponseRecorder, uint64, bool) {
	t.Helper()
	var gotID uint64
	var gotOK bool
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotID, gotOK = auth.UserID(r.Context())
		w.WriteHeader(http.StatusOK)
	}))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	if header != "" {
		req.Header.Set("Authorization", header)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec, gotID, gotOK
}

func TestTokenRoundTrip(t *testing.T) {
	tok, err := auth.IssueAccess(secret, 42, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	rec, id, ok := probe(t, auth.Middleware(secret), "Bearer "+tok)
	if rec.Code != http.StatusOK || !ok || id != 42 {
		t.Fatalf("code=%d id=%d ok=%v", rec.Code, id, ok)
	}
}

func TestMiddlewareRejectsMissingExpiredAndTamperedToken(t *testing.T) {
	valid, _ := auth.IssueAccess(secret, 1, time.Minute)
	expired, _ := auth.IssueAccess(secret, 1, -time.Minute)
	wrongKey, _ := auth.IssueAccess([]byte("other"), 1, time.Minute)
	tampered := valid[:len(valid)-2] + "xx"
	cases := map[string]string{
		"missing":   "",
		"expired":   "Bearer " + expired,
		"tampered":  "Bearer " + tampered,
		"wrong key": "Bearer " + wrongKey,
		"garbage":   "Bearer not-a-jwt",
		"no scheme": valid,
	}
	for name, hdr := range cases {
		t.Run(name, func(t *testing.T) {
			rec, _, ok := probe(t, auth.Middleware(secret), hdr)
			if rec.Code != http.StatusUnauthorized || ok {
				t.Fatalf("code=%d ok=%v", rec.Code, ok)
			}
			if body := rec.Body.String(); !contains(body, `"code":"unauthorized"`) {
				t.Fatalf("body = %s", body)
			}
		})
	}
}

func TestOptionalAllowsAnonymous(t *testing.T) {
	rec, _, ok := probe(t, auth.Optional(secret), "")
	if rec.Code != http.StatusOK || ok {
		t.Fatalf("anonymous: code=%d ok=%v", rec.Code, ok)
	}
	tok, _ := auth.IssueAccess(secret, 7, time.Minute)
	rec, id, ok := probe(t, auth.Optional(secret), "Bearer "+tok)
	if rec.Code != http.StatusOK || !ok || id != 7 {
		t.Fatalf("authed: code=%d id=%d ok=%v", rec.Code, id, ok)
	}
	// An invalid token is treated as anonymous, not as an error.
	rec, _, ok = probe(t, auth.Optional(secret), "Bearer garbage")
	if rec.Code != http.StatusOK || ok {
		t.Fatalf("invalid: code=%d ok=%v", rec.Code, ok)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
