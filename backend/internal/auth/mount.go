package auth

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/ratelimit"
)

// Mount registers the auth routes on the /api/v1 router. Logins,
// registrations and refreshes are rate limited per client IP, wrong
// passwords per account (see config.Limits).
func Mount(r chi.Router, d app.Deps) {
	lim := d.Cfg.Limits
	h := &handler{
		svc:      &service{db: d.DB, secret: d.Cfg.JWTSecret, uploadDir: d.Cfg.UploadDir},
		failures: ratelimit.New(lim.LoginFailures),
	}
	r.With(ratelimit.ByIP(ratelimit.New(lim.Register))).Post("/auth/register", h.register)
	r.With(ratelimit.ByIP(ratelimit.New(lim.Login))).Post("/auth/login", h.login)
	r.With(ratelimit.ByIP(ratelimit.New(lim.Refresh))).Post("/auth/refresh", h.refresh)
	mw := Middleware(d.Cfg.JWTSecret)
	r.With(mw).Get("/me", h.me)
	r.With(mw).Put("/me/password", h.changePassword)
	r.With(mw).Post("/me/delete", h.deleteAccount)
}
