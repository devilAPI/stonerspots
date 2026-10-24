package auth

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
)

// Mount registers the auth routes on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{svc: &service{db: d.DB, secret: d.Cfg.JWTSecret, uploadDir: d.Cfg.UploadDir}}
	r.Post("/auth/register", h.register)
	r.Post("/auth/login", h.login)
	r.Post("/auth/refresh", h.refresh)
	mw := Middleware(d.Cfg.JWTSecret)
	r.With(mw).Get("/me", h.me)
	r.With(mw).Put("/me/password", h.changePassword)
	r.With(mw).Post("/me/delete", h.deleteAccount)
}
