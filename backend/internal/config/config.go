// Package config loads runtime configuration from environment variables.
package config

import (
	"errors"
	"os"
	"strings"
)

const defaultDatabaseURL = "stonerspots:stonerspots@tcp(127.0.0.1:3307)/stonerspots?parseTime=true&multiStatements=true"

type Config struct {
	DatabaseURL string
	JWTSecret   []byte
	UploadDir   string
	Addr        string
	// PublicBaseURL is the externally visible origin of this server
	// (e.g. "http://localhost:8080"), used to build absolute photo URLs.
	PublicBaseURL string
	// GeocoderURL is the base URL of a Nominatim-compatible geocoder.
	GeocoderURL string
	// AllowedOrigins are the browser origins (e.g. "https://devilapi.github.io")
	// the web app may call this API from (CORS). Empty: no cross-origin access.
	AllowedOrigins []string
}

// Load reads configuration from the environment. JWT_SECRET is required.
func Load() (Config, error) {
	c := Config{
		DatabaseURL:   getenv("DATABASE_URL", defaultDatabaseURL),
		JWTSecret:     []byte(os.Getenv("JWT_SECRET")),
		UploadDir:     getenv("UPLOAD_DIR", "./uploads"),
		Addr:          getenv("ADDR", ":8080"),
		PublicBaseURL: getenv("PUBLIC_BASE_URL", "http://localhost:8080"),
		GeocoderURL:   getenv("GEOCODER_URL", "https://nominatim.openstreetmap.org"),
		// comma-separated, e.g. ALLOWED_ORIGINS=https://devilapi.github.io
		AllowedOrigins: splitList(os.Getenv("ALLOWED_ORIGINS")),
	}
	if len(c.JWTSecret) == 0 {
		return Config{}, errors.New("JWT_SECRET must be set")
	}
	return c, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func splitList(s string) []string {
	var out []string
	for _, v := range strings.Split(s, ",") {
		if v = strings.TrimRight(strings.TrimSpace(v), "/"); v != "" {
			out = append(out, v)
		}
	}
	return out
}
