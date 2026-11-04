// Package admin has the moderation endpoints for admins: reports, users and
// spots. Every route requires a valid token AND is_admin in the database.
package admin

import (
	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/photos"
)

// Mount registers the admin routes on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := handler{
		repo:        repo{db: d.DB, uploadDir: d.Cfg.UploadDir, base: d.Cfg.PublicBaseURL},
		photos:      photos.StorageFor(d),
		updateDir:   d.Cfg.UpdateDir,
		versionFile: versionFileNextTo(),
		guard:       auth.GuardFor(d),
	}
	g := r.With(auth.Middleware(d.Cfg.JWTSecret), auth.RequireAdmin(d))
	g.Get("/admin/reports", h.reports)
	g.Get("/admin/users", h.users)
	g.Get("/admin/spots", h.spots)
	g.Delete("/admin/spots/{id}", h.deleteSpot)
	g.Patch("/admin/spots/{id}", h.patchSpot)
	g.Delete("/admin/reviews/{id}", h.deleteReview)
	g.Delete("/admin/comments/{id}", h.deleteComment)
	g.Delete("/admin/updates/{id}", h.deleteUpdate)
	g.Patch("/admin/updates/{id}", h.patchUpdate)
	g.Get("/admin/tags", h.listTags)
	g.Post("/admin/tags", h.createTag)
	g.Patch("/admin/tags/{tag}", h.patchTag)
	g.Delete("/admin/tags/{tag}", h.deleteTag)
	g.Patch("/admin/users/{id}", h.patchUser)
	g.Delete("/admin/users/{id}/avatar", h.deleteAvatar)
	g.Post("/admin/users/bulk", h.bulkUsers)
	g.Post("/admin/spots/bulk", h.bulkSpots)
	g.Get("/admin/system", h.system)
	g.Post("/admin/system/update", h.requestUpdate)
	g.Delete("/admin/reports/{id}", h.deleteReport)
	g.Post("/admin/reports/dismiss", h.dismiss)

	// Photo moderation
	g.Get("/admin/photos", h.listPhotos)
	g.Patch("/admin/photos/{id}", h.patchPhoto)
	g.Post("/admin/photos/{id}/rotate", h.rotatePhoto)
	g.Delete("/admin/photos/{id}", h.deletePhoto)

	// TOTP 2FA for admins (see auth/guard.go). Setting it up stays open to
	// admins without 2FA when require_admin_totp refuses them elsewhere.
	setup := r.With(auth.Middleware(d.Cfg.JWTSecret), auth.RequireAdminSetup(d))
	setup.Get("/admin/2fa", h.totpStatus)
	setup.Post("/admin/2fa/enable", h.totpEnableStart)
	setup.Post("/admin/2fa/verify", h.totpVerify)
	g.Post("/admin/2fa/disable", h.totpDisable)
	g.Post("/admin/2fa/session", h.guard.NewAdminSession)
}
