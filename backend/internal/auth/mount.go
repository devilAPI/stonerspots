package auth

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
)

// Mount registers the auth routes on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{svc: &service{db: d.DB, secret: d.Cfg.JWTSecret}}
	r.Post("/auth/register", h.register)
	r.Post("/auth/login", h.login)
	r.Post("/auth/refresh", h.refresh)
	r.With(Middleware(d.Cfg.JWTSecret)).Get("/me", h.me)
}
