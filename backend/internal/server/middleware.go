package server

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"net/http"
	"strings"
	"time"

	"stonerspots/backend/internal/httpx"
)

// securityHeaders sets headers that keep browsers from misusing responses:
// the API only serves JSON and photos, never pages, so nothing may be
// framed, sniffed or run as a document. Photos are loaded cross-origin by
// the web app (GitHub Pages), hence Cross-Origin-Resource-Policy:
// cross-origin. HSTS only makes sense when the API is reached via https.
func securityHeaders(publicBaseURL string) func(http.Handler) http.Handler {
	https := strings.HasPrefix(publicBaseURL, "https://")
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := w.Header()
			h.Set("X-Content-Type-Options", "nosniff")
			h.Set("X-Frame-Options", "DENY")
			h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
			h.Set("Referrer-Policy", "no-referrer")
			h.Set("Cross-Origin-Resource-Policy", "cross-origin")
			// personal data must not end up in shared caches; media overrides it
			h.Set("Cache-Control", "no-store")
			if https {
				h.Set("Strict-Transport-Security", "max-age=31536000")
			}
			next.ServeHTTP(w, r)
		})
	}
}

// statusRecorder remembers the status code a handler wrote.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	if s.status == 0 {
		s.status = code
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	if s.status == 0 {
		s.status = http.StatusOK
	}
	return s.ResponseWriter.Write(b)
}

// Unwrap lets http.ResponseController reach the real writer.
func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// logProblems gives every request an id (X-Request-Id response header) and
// logs server errors and rate-limited requests with it, so failures and
// attacks show up in the journal. Paths are logged without query strings,
// which may hold search terms.
func logProblems(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := newRequestID()
		w.Header().Set("X-Request-Id", id)
		rec := &statusRecorder{ResponseWriter: w}
		start := time.Now()
		defer func() {
			if rec.status >= 500 || rec.status == http.StatusTooManyRequests {
				log.Printf("%d %s %q %s ip=%s id=%s", rec.status, r.Method, r.URL.Path,
					time.Since(start).Round(time.Millisecond), httpx.ClientIP(r), id)
			}
		}()
		next.ServeHTTP(rec, r)
	})
}

func newRequestID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// bodyLimit wraps the request body with MaxBytesReader as a global safety net.
// Per-handler limits (e.g. 8 MB for uploads) still apply and are more precise.
func bodyLimit(maxBytes int64) func(http.Handler) http.Handler {
	if maxBytes <= 0 {
		maxBytes = 10 << 20 // 10 MB default
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
			next.ServeHTTP(w, r)
		})
	}
}
