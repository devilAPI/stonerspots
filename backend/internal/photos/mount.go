package photos

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/ratelimit"
)

// Mount registers POST /photos (auth, rate limited per user) and GET
// /media/* (public static files). It is called on the /api/v1 router, so
// media is served at /api/v1/media/*.
func Mount(r chi.Router, d app.Deps) {
	base := strings.TrimRight(d.Cfg.PublicBaseURL, "/") + "/api/v1/media"
	h := &handler{d: d, storage: NewLocalStorage(d.Cfg.UploadDir, base)}
	perUser := ratelimit.Middleware(ratelimit.New(d.Cfg.Limits.Uploads), func(r *http.Request) string {
		if id, ok := auth.UserID(r.Context()); ok {
			return "user:" + strconv.FormatUint(id, 10)
		}
		return ""
	})
	r.With(auth.Middleware(d.Cfg.JWTSecret), perUser).Post("/photos", h.upload)
	r.Get("/media/*", h.serveMedia)
}
