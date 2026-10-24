// Package admin has the moderation endpoints for admins: reports, users and
// spots. Every route requires a valid token AND is_admin in the database.
package admin

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
)

// Mount registers the admin routes on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := handler{repo: repo{db: d.DB, uploadDir: d.Cfg.UploadDir}}
	g := r.With(auth.Middleware(d.Cfg.JWTSecret), auth.RequireAdmin(d.DB))
	g.Get("/admin/reports", h.reports)
	g.Get("/admin/users", h.users)
	g.Get("/admin/spots", h.spots)
	g.Delete("/admin/spots/{id}", h.deleteSpot)
}
