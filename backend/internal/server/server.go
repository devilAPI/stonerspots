// Package server assembles the HTTP router. Feature modules register their
// own routes in Mount; this file should not need to change for them.
package server

import (
	"net/http"

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
	"stonerspots/backend/internal/spots"
)

func New(d app.Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RealIP, middleware.Recoverer)
	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/health", health(d))
		auth.Mount(r, d)
		spots.Mount(r, d)
		photos.Mount(r, d)
		feed.Mount(r, d)
		engagement.Mount(r, d)
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
