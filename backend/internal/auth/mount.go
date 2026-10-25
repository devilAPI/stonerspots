package auth

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/hibp"
	"stonerspots/backend/internal/mail"
	"stonerspots/backend/internal/pow"
	"stonerspots/backend/internal/ratelimit"
)

// Mount registers the auth routes on the /api/v1 router. Logins,
// registrations and refreshes are rate limited per client IP, wrong
// passwords per account (see config.Limits).
func Mount(r chi.Router, d app.Deps) {
	MountWithOptions(r, d, MountOptions{})
}

// MountForTest registers the auth routes with test options (no PoW).
func MountForTest(r chi.Router, d app.Deps) {
	MountWithOptions(r, d, MountOptions{DisablePoW: true})
}

// MountOptions configures optional features for Mount.
type MountOptions struct {
	// DisablePoW disables proof-of-work requirement for registration.
	DisablePoW bool
}

// MountWithOptions registers the auth routes with options.
func MountWithOptions(r chi.Router, d app.Deps, opts MountOptions) {
	lim := d.Cfg.Limits
	mc := mail.NewClient(mail.Config{
		Host:     d.Cfg.Mail.Host,
		Port:     d.Cfg.Mail.Port,
		Username: d.Cfg.Mail.Username,
		Password: d.Cfg.Mail.Password,
		From:     d.Cfg.Mail.From,
	})
	var powChallenge *pow.Challenge
	if !opts.DisablePoW {
		powChallenge = pow.NewChallenge("register", 18) // Difficulty 18 ~ 2^18 iterations
	}
	h := &handler{
		svc:      &service{db: d.DB, secret: d.Cfg.JWTSecret, uploadDir: d.Cfg.UploadDir, mail: mc},
		hibp:     hibp.NewClient(),
		failures: ratelimit.New(lim.LoginFailures),
		pow:      powChallenge,
	}
	r.With(ratelimit.ByIP(ratelimit.New(lim.Register))).Post("/auth/register", h.register)
	r.Get("/auth/pow-challenge", h.powChallenge)
	r.Post("/auth/verify-email", h.verifyEmail)
	r.Post("/auth/forgot-password", h.forgotPassword)
	r.Post("/auth/reset-password", h.resetPassword)
	r.With(ratelimit.ByIP(ratelimit.New(lim.Login))).Post("/auth/login", h.login)
	r.With(ratelimit.ByIP(ratelimit.New(lim.Refresh))).Post("/auth/refresh", h.refresh)
	mw := Middleware(d.Cfg.JWTSecret)
	r.With(mw).Get("/me", h.me)
	r.With(mw).Put("/me/password", h.changePassword)
	r.With(mw).Post("/me/delete", h.deleteAccount)
}
