package photos

import (
	"strings"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
)

// Mount registers POST /photos (auth) and GET /media/* (public static files).
// It is called on the /api/v1 router, so media is served at /api/v1/media/*.
func Mount(r chi.Router, d app.Deps) {
	base := strings.TrimRight(d.Cfg.PublicBaseURL, "/") + "/api/v1/media"
	h := &handler{d: d, storage: NewLocalStorage(d.Cfg.UploadDir, base)}
	r.With(auth.Middleware(d.Cfg.JWTSecret)).Post("/photos", h.upload)
	r.Get("/media/*", h.serveMedia)
}
