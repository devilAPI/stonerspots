// Package legal serves the operator details for the app's legal notice
// (Impressum, § 5 DDG) and privacy policy. They come from the legal:
// section of the server's config.yaml, so nothing personal is kept in the
// repository or compiled into the app.
package legal

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/ratelimit"
)

// Info is the answer of GET /legal. Configured is true only when name,
// address and email are set; the app shows nothing of the rest otherwise.
type Info struct {
	Configured          bool   `json:"configured"`
	OperatorName        string `json:"operator_name"`
	Address             string `json:"address"`
	Email               string `json:"email"`
	Phone               string `json:"phone"`
	ResponsiblePerson   string `json:"responsible_person"`
	Country             string `json:"country"`
	PrivacyContactEmail string `json:"privacy_contact_email"`
	Extra               string `json:"extra"`
}

// FromConfig builds the answer, with the defaults for the optional fields.
func FromConfig(c config.LegalConfig) Info {
	if !c.Configured() {
		// half-filled or example values are not shown at all
		return Info{}
	}
	l := c.WithDefaults()
	return Info{
		Configured:          true,
		OperatorName:        l.OperatorName,
		Address:             l.Address,
		Email:               l.Email,
		Phone:               l.Phone,
		ResponsiblePerson:   l.ResponsiblePerson,
		Country:             l.Country,
		PrivacyContactEmail: l.PrivacyContactEmail,
		Extra:               l.Extra,
	}
}

// CacheControl lets browsers and the app keep the answer for an hour; it is
// the same for everyone and changes only with the config.
const CacheControl = "public, max-age=3600"

// Mount registers GET /legal (no login), limited per IP like the other
// public reads that have their own limit (search, feed).
func Mount(r chi.Router, d app.Deps) {
	info := FromConfig(d.Cfg.Legal)
	r.With(ratelimit.ByIP(ratelimit.New(d.Cfg.Limits.Search))).Get("/legal", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Cache-Control", CacheControl)
		httpx.JSON(w, http.StatusOK, info)
	})
}
