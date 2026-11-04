// Package app holds the dependencies shared by every module. It imports
// nothing from other internal modules, so there are no import cycles.
package app

import (
	"database/sql"
	"strings"

	"stonerspots/backend/internal/config"
)

type Deps struct {
	DB  *sql.DB
	Cfg config.Config
}

// MediaURL is the public URL of an upload dir file served at GET /media/*.
func MediaURL(publicBaseURL, key string) string {
	return strings.TrimRight(publicBaseURL, "/") + "/api/v1/media/" + key
}

// AvatarURL is the public URL of a user's avatar, or nil when there is none
// (the avatar_url field of every user object).
func AvatarURL(publicBaseURL string, key sql.NullString) *string {
	if !key.Valid || key.String == "" {
		return nil
	}
	u := MediaURL(publicBaseURL, key.String)
	return &u
}
