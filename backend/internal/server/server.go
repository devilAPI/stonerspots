// Package server assembles the HTTP router. Feature modules register their
// own routes in Mount; this file should not need to change for them.
package server

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"stonerspots/backend/internal/admin"
	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/engagement"
	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/geocode"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/photos"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/reviews"
	"stonerspots/backend/internal/spots"
)

// HTTPServer wraps h with timeouts, so slow or idle clients cannot hold
// connections (and memory) forever. Reads and writes may take up to two
// minutes: a phone on a bad connection uploading an 8 MB photo.
func HTTPServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       2 * time.Minute,
		WriteTimeout:      2 * time.Minute,
		IdleTimeout:       2 * time.Minute,
		MaxHeaderBytes:    32 << 10,
	}
}

func New(d app.Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(
		// X-Forwarded-For only from configured proxies (no middleware.RealIP:
		// it believes any client)
		httpx.WithClientIP(d.Cfg.TrustedProxies),
		logProblems,
		middleware.Recoverer,
		securityHeaders(d.Cfg.PublicBaseURL),
		// CORS first, so the web app can read a 429 instead of a CORS error
		cors(d.Cfg.AllowedOrigins),
		ratelimit.ByIP(ratelimit.New(d.Cfg.Limits.PerIP)),
		bodyLimit(d.Cfg.MaxBodyBytes),
	)

	quotaTracker := quotas.NewTracker(quotas.Config{
		SpotsPerDay:   d.Cfg.Limits.SpotsPerDay,
		UpdatesPerDay: d.Cfg.Limits.UpdatesPerDay,
		ReviewsPerDay: d.Cfg.Limits.ReviewsPerDay,
		ReportsPerDay: d.Cfg.Limits.ReportsPerDay,
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/health", health(d))
		auth.MountWithOptions(r, d, auth.MountOptions{DisablePoW: d.Cfg.DisablePoW})
		spots.Mount(r, d, quotaTracker)
		photos.Mount(r, d)
		feed.Mount(r, d, quotaTracker)
		engagement.Mount(r, d, quotaTracker)
		reviews.Mount(r, d, quotaTracker)
		geocode.Mount(r, d)
		admin.Mount(r, d)
	})
	return r
}

func health(d app.Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		if err := d.DB.PingContext(req.Context()); err != nil {
			httpx.JSON(w, http.StatusServiceUnavailable, map[string]string{"status": "degraded", "db": "error"})
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok", "db": "ok"})
	}
}
