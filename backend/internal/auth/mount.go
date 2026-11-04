package auth

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
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
	// UnreadActivity counts a user's unread activity for GET /me. It is
	// passed in because the activity package depends on auth, not the
	// other way round. nil: GET /me reports 0.
	UnreadActivity func(ctx context.Context, userID uint64) (int, error)

	// for tests (export_test.go): replace SMTP, HIBP and the goroutine
	// that runs mail jobs
	mailer mailer
	hibp   *hibp.Client
	async  func(func())
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
	var powIssuer *pow.Issuer
	if !opts.DisablePoW {
		difficulty := d.Cfg.PowDifficulty
		if difficulty <= 0 {
			difficulty = config.DefaultPowDifficulty
		}
		// its own key: a challenge MAC can never be confused with a token
		powIssuer = pow.NewIssuer(deriveKey(d.Cfg.JWTSecret, "pow-v1"), "register", difficulty)
	}
	var m mailer = mc
	if opts.mailer != nil {
		m = opts.mailer
	}
	hc := hibp.NewClient()
	if opts.hibp != nil {
		hc = opts.hibp
	}
	h := &handler{
		svc: &service{db: d.DB, secret: d.Cfg.JWTSecret, uploadDir: d.Cfg.UploadDir, base: d.Cfg.PublicBaseURL,
			appURL: d.Cfg.AppBaseURL, mail: m, async: opts.async},
		hibp:           hc,
		failures:       ratelimit.New(lim.LoginFailures),
		pow:            powIssuer,
		forgotPerEmail: ratelimit.New(lim.ForgotPasswordEmail),

		unreadActivity: opts.UnreadActivity,
	}
	r.With(ratelimit.ByIP(ratelimit.New(lim.Register))).Post("/auth/register", h.register)
	r.Get("/auth/pow-challenge", h.powChallenge)
	r.Post("/auth/verify-email", h.verifyEmail)
	r.With(ratelimit.ByIP(ratelimit.New(lim.ForgotPassword))).Post("/auth/forgot-password", h.forgotPassword)
	r.Post("/auth/reset-password", h.resetPassword)
	r.With(ratelimit.ByIP(ratelimit.New(lim.Login))).Post("/auth/login", h.login)
	r.With(ratelimit.ByIP(ratelimit.New(lim.Refresh))).Post("/auth/refresh", h.refresh)
	mw := Middleware(d.Cfg.JWTSecret)
	r.With(mw).Get("/me", h.me)
	r.With(mw).Put("/me/password", h.changePassword)
	r.With(mw).Post("/me/delete", h.deleteAccount)
}

// deriveKey derives a key for one purpose from the JWT secret, so that
// tokens, proof-of-work challenges and admin 2FA sessions never share a key.
func deriveKey(secret []byte, purpose string) []byte {
	m := hmac.New(sha256.New, secret)
	m.Write([]byte("stonerspots/" + purpose))
	return m.Sum(nil)
}
