package feed

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
)

// Mount registers feed and update routes on the /api/v1 router. Full paths are
// registered (no r.Route("/spots")) because other modules share the prefix.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{db: d.DB, base: d.Cfg.PublicBaseURL}
	r.With(auth.Middleware(d.Cfg.JWTSecret)).Post("/spots/{id}/updates", h.postUpdate)
	r.Get("/feed", h.getFeed)
}
