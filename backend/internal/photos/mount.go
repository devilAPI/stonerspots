package photos

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/ratelimit"
)

// Mount registers POST /photos and PUT /me/avatar (auth, rate limited per
// user, one shared limit), DELETE /me/avatar (auth) and GET
// /media/* (public, visible content only). It is called on the /api/v1 router, so
// media is served at /api/v1/media/*.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{d: d, storage: StorageFor(d)}
	perUser := ratelimit.Middleware(ratelimit.New(uploadRule(d.Cfg.Limits.Uploads)), func(r *http.Request) string {
		if id, ok := auth.UserID(r.Context()); ok {
			return "user:" + strconv.FormatUint(id, 10)
		}
		return ""
	})
	r.With(auth.Middleware(d.Cfg.JWTSecret), perUser).Post("/photos", h.upload)
	// avatars share the photo upload limit (same limiter, same key)
	r.With(auth.Middleware(d.Cfg.JWTSecret), perUser).Put("/me/avatar", h.putAvatar)
	r.With(auth.Middleware(d.Cfg.JWTSecret)).Delete("/me/avatar", h.deleteAvatar)
	r.Get("/media/*", h.serveMedia)
}

// uploadBurst is how many uploads (photos and avatars) one user can send
// back to back. A ratelimit.Rule bursts up to its N, so uploadRule keeps
// the configured rate (N per Per) with this smaller burst: decoding is the
// expensive part of the API (see decodelimit.go).
const uploadBurst = 5

// uploadRule turns rule (e.g. 30 per hour) into the same rate in bursts of
// at most uploadBurst (5 per 10 minutes).
func uploadRule(rule ratelimit.Rule) ratelimit.Rule {
	if rule.Off() || rule.N <= uploadBurst {
		return rule
	}
	return ratelimit.Rule{N: uploadBurst, Per: rule.Per * uploadBurst / time.Duration(rule.N)}
}

// StorageFor is the upload dir storage whose URLs point at GET /media/*.
func StorageFor(d app.Deps) Storage {
	return NewLocalStorage(d.Cfg.UploadDir, strings.TrimRight(d.Cfg.PublicBaseURL, "/")+"/api/v1/media")
}
