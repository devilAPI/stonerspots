package feed

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/ratelimit"
)

// Mount registers feed and update routes on the /api/v1 router. Full paths are
// registered (no r.Route("/spots")) because other modules share the prefix.
func Mount(r chi.Router, d app.Deps, quota *quotas.Tracker) {
	h := &handler{db: d.DB, base: d.Cfg.PublicBaseURL, uploadDir: d.Cfg.UploadDir, quota: quota, guard: auth.GuardFor(d)}
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Post("/spots/{id}/updates", h.postUpdate)
	authed.Patch("/updates/{id}", h.patchUpdate)
	authed.Delete("/updates/{id}", h.deleteUpdate)
	// Optional login: following=true needs to know the caller.
	// expensive queries: their own, tighter per-IP limit
	r.With(ratelimit.ByIP(ratelimit.New(d.Cfg.Limits.Search)), auth.Optional(d.Cfg.JWTSecret)).Get("/feed", h.getFeed)
}
