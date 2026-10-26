// Package config loads runtime configuration from an optional YAML file and
// environment variables. Precedence: environment > file > defaults.
//
// The file is $CONFIG_FILE, or ./config.yaml when that exists. See
// backend/config.example.yaml for every key.
package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"gopkg.in/yaml.v3"

	"stonerspots/backend/internal/ratelimit"
)

const (
	defaultDatabaseURL = "stonerspots:stonerspots@tcp(127.0.0.1:3307)/stonerspots?parseTime=true&multiStatements=true"
	defaultFile        = "config.yaml"
)

type Config struct {
	DatabaseURL string
	JWTSecret   []byte
	UploadDir   string
	Addr        string
	// MigrationsDir holds the *.up.sql / *.down.sql files applied on start.
	MigrationsDir string
	// PublicBaseURL is the externally visible origin of this server
	// (e.g. "http://localhost:8080"), used to build absolute photo URLs.
	PublicBaseURL string
	// GeocoderURL is the base URL of a Nominatim-compatible geocoder.
	GeocoderURL string
	// OverpassURL is the Overpass API interpreter endpoint for the public
	// transport stops on the map.
	OverpassURL string
	// AllowedOrigins are the browser origins (e.g. "https://devilapi.github.io")
	// the web app may call this API from (CORS). Empty: no cross-origin access.
	AllowedOrigins []string

	// TrustedProxies are the reverse proxies whose X-Forwarded-For header
	// names the real client. Requests from anywhere else are taken by their
	// connection address, so clients cannot fake their IP (rate limits).
	TrustedProxies []netip.Prefix

	// MaxBodyBytes is the maximum request body size accepted by the server
	// as a safety net (per-handler limits still apply). Default 10 MB.
	MaxBodyBytes int64

	// Limits are the rate limits; Read fills in DefaultLimits. A zero rule
	// (as in a Config built by hand, e.g. in tests) limits nothing.
	Limits Limits

	// Mail is the SMTP configuration for transactional emails.
	// Zero value disables all mail features (verification, password reset).
	Mail MailConfig

	// DisablePoW disables proof-of-work requirement for registration.
	// Used in tests to avoid PoW overhead.
	DisablePoW bool
}

// MailConfig holds SMTP settings. Empty Host disables mail.
type MailConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

// Limits are the per-client rate limits of the API.
type Limits struct {
	PerIP         ratelimit.Rule // every request, per client IP
	Login         ratelimit.Rule // login attempts per IP
	LoginFailures ratelimit.Rule // wrong passwords per account (email)
	Register      ratelimit.Rule // new accounts per IP
	Refresh       ratelimit.Rule // token refreshes per IP
	Uploads       ratelimit.Rule // photo uploads per user

	// Daily quotas per user (reset at midnight UTC). Zero = unlimited.
	SpotsPerDay     int // new spots per user per day
	UpdatesPerDay   int // spot updates per user per day
	ReviewsPerDay   int // reviews per user per day
	ReportsPerDay   int // reports per user per day
}

// DefaultLimits are generous for people and tight for scripts. The feed and
// map fetch many photos, hence the high per-IP budget.
func DefaultLimits() Limits {
	return Limits{
		PerIP:         ratelimit.Rule{N: 600, Per: time.Minute},
		Login:         ratelimit.Rule{N: 10, Per: time.Minute},
		LoginFailures: ratelimit.Rule{N: 20, Per: time.Hour},
		Register:      ratelimit.Rule{N: 5, Per: time.Hour},
		Refresh:       ratelimit.Rule{N: 30, Per: time.Minute},
		Uploads:       ratelimit.Rule{N: 30, Per: time.Hour},
		SpotsPerDay:     10,
		UpdatesPerDay:   50,
		ReviewsPerDay:   20,
		ReportsPerDay:   10,
	}
}

// file mirrors config.example.yaml.
type file struct {
	Addr           string   `yaml:"addr"`
	PublicBaseURL  string   `yaml:"public_base_url"`
	AllowedOrigins []string `yaml:"allowed_origins"`
	JWTSecret      string   `yaml:"jwt_secret"`
	UploadDir      string   `yaml:"upload_dir"`
	MigrationsDir  string   `yaml:"migrations_dir"`
	GeocoderURL    string   `yaml:"geocoder_url"`
	OverpassURL    string   `yaml:"overpass_url"`
	TrustedProxies []string `yaml:"trusted_proxies"`
	Database       database `yaml:"database"`
	Limits         fileLimits `yaml:"limits"`
	MaxBodyBytes   int64    `yaml:"max_body_bytes"`
	Mail           fileMail `yaml:"mail"`
}

type fileMail struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	From     string `yaml:"from"`
}

type fileLimits struct {
	PerIP         fileRule `yaml:"per_ip"`
	Login         fileRule `yaml:"login"`
	LoginFailures fileRule `yaml:"login_failures"`
	Register      fileRule `yaml:"register"`
	Refresh       fileRule `yaml:"refresh"`
	Uploads       fileRule `yaml:"uploads"`
	SpotsPerDay     int `yaml:"spots_per_day"`
	UpdatesPerDay   int `yaml:"updates_per_day"`
	ReviewsPerDay   int `yaml:"reviews_per_day"`
	ReportsPerDay   int `yaml:"reports_per_day"`
}

type fileRule struct {
	N   int    `yaml:"n"`
	Per string `yaml:"per"`
}

type database struct {
	// URL is a complete DSN; when set, the other fields are ignored.
	URL      string `yaml:"url"`
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	User     string `yaml:"user"`
	Password string `yaml:"password"`
	Name     string `yaml:"name"`
}

// dsn builds the driver DSN, falling back to the local dev database for
// fields left empty. Returns "" when no database field is set at all.
func (d database) dsn() string {
	if d.URL != "" {
		return d.URL
	}
	if d == (database{}) {
		return ""
	}
	c := mysql.NewConfig()
	c.Net = "tcp"
	c.Addr = net.JoinHostPort(or(d.Host, "127.0.0.1"), strconv.Itoa(orInt(d.Port, 3307)))
	c.User = or(d.User, "stonerspots")
	c.Passwd = or(d.Password, "stonerspots")
	c.DBName = or(d.Name, "stonerspots")
	c.ParseTime = true
	c.MultiStatements = true // migrations need it
	return c.FormatDSN()
}

// MinSecretLen is the shortest jwt_secret accepted for a public server:
// whoever knows the secret can sign tokens for any user, admins included.
const MinSecretLen = 32

// knownSecrets are published in this repository (examples, docs), so they
// are as good as no secret on a public server.
var knownSecrets = []string{"change-me", "dev-secret-change-me"}

// Load reads the configuration and requires a strong JWT secret (the API
// server). A weak one is only tolerated, with a warning, while the API is
// reachable at localhost.
func Load() (Config, error) {
	c, err := Read()
	if err != nil {
		return Config{}, err
	}
	if len(c.JWTSecret) == 0 {
		return Config{}, errors.New("JWT_SECRET must be set (env or jwt_secret in the config file)")
	}
	if problem := weakSecret(c.JWTSecret); problem != "" {
		if !isLocal(c.PublicBaseURL) {
			return Config{}, fmt.Errorf("jwt_secret %s; generate one with: openssl rand -hex 32", problem)
		}
		log.Printf("WARNING: jwt_secret %s; fine for local development only", problem)
	}
	return c, nil
}

func weakSecret(s []byte) string {
	for _, k := range knownSecrets {
		if string(s) == k {
			return "is an example value from the repository"
		}
	}
	if len(s) < MinSecretLen {
		return fmt.Sprintf("is shorter than %d characters", MinSecretLen)
	}
	return ""
}

// isLocal reports whether the public URL points at this machine only.
func isLocal(publicURL string) bool {
	u, err := url.Parse(publicURL)
	if err != nil {
		return false
	}
	switch u.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return true
	}
	return false
}

// parseProxies reads IPs or CIDR ranges (e.g. 127.0.0.1, 10.0.0.0/8).
func parseProxies(list []string) ([]netip.Prefix, error) {
	var out []netip.Prefix
	for _, v := range list {
		if v = strings.TrimSpace(v); v == "" {
			continue
		}
		if p, err := netip.ParsePrefix(v); err == nil {
			out = append(out, p.Masked())
			continue
		}
		a, err := netip.ParseAddr(v)
		if err != nil {
			return nil, fmt.Errorf("trusted_proxies: %q is neither an IP nor a CIDR range", v)
		}
		out = append(out, netip.PrefixFrom(a.Unmap(), a.Unmap().BitLen()))
	}
	return out, nil
}

// Read reads the configuration without validating it (for tools like
// makeadmin that only need the database).
func Read() (Config, error) {
	f, err := readFile()
	if err != nil {
		return Config{}, err
	}
	origins := splitList(os.Getenv("ALLOWED_ORIGINS"))
	if origins == nil {
		origins = splitList(strings.Join(f.AllowedOrigins, ","))
	}
	proxyList := f.TrustedProxies
	if env := os.Getenv("TRUSTED_PROXIES"); env != "" {
		proxyList = strings.Split(env, ",")
	}
	proxies, err := parseProxies(proxyList)
	if err != nil {
		return Config{}, err
	}
	return Config{
		DatabaseURL:    getenv("DATABASE_URL", or(f.Database.dsn(), defaultDatabaseURL)),
		JWTSecret:      []byte(getenv("JWT_SECRET", f.JWTSecret)),
		UploadDir:      getenv("UPLOAD_DIR", or(f.UploadDir, "./uploads")),
		Addr:           getenv("ADDR", or(f.Addr, ":8080")),
		MigrationsDir:  getenv("MIGRATIONS_DIR", or(f.MigrationsDir, "migrations")),
		PublicBaseURL:  strings.TrimRight(getenv("PUBLIC_BASE_URL", or(f.PublicBaseURL, "http://localhost:8080")), "/"),
		GeocoderURL:    getenv("GEOCODER_URL", or(f.GeocoderURL, "https://nominatim.openstreetmap.org")),
		OverpassURL:    getenv("OVERPASS_URL", or(f.OverpassURL, "https://overpass-api.de/api/interpreter")),
		AllowedOrigins: origins,
		TrustedProxies: proxies,
		MaxBodyBytes:   getenvInt64("MAX_BODY_BYTES", f.MaxBodyBytes, 10<<20),
		Limits:         parseLimits(f.Limits),
		Mail: MailConfig{
			Host:     getenv("MAIL_HOST", f.Mail.Host),
			Port:     getenvInt("MAIL_PORT", f.Mail.Port, 587),
			Username: getenv("MAIL_USERNAME", f.Mail.Username),
			Password: getenv("MAIL_PASSWORD", f.Mail.Password),
			From:     getenv("MAIL_FROM", f.Mail.From),
		},
	}, nil
}

// parseLimits converts fileLimits to ratelimit.Rules, using defaults for any
// zero values so that a partial config still works.
func parseLimits(f fileLimits) Limits {
	def := DefaultLimits()
	return Limits{
		PerIP:         ruleOrDefault(f.PerIP, def.PerIP),
		Login:         ruleOrDefault(f.Login, def.Login),
		LoginFailures: ruleOrDefault(f.LoginFailures, def.LoginFailures),
		Register:      ruleOrDefault(f.Register, def.Register),
		Refresh:       ruleOrDefault(f.Refresh, def.Refresh),
		Uploads:       ruleOrDefault(f.Uploads, def.Uploads),
		SpotsPerDay:     intOrDefault(f.SpotsPerDay, def.SpotsPerDay),
		UpdatesPerDay:   intOrDefault(f.UpdatesPerDay, def.UpdatesPerDay),
		ReviewsPerDay:   intOrDefault(f.ReviewsPerDay, def.ReviewsPerDay),
		ReportsPerDay:   intOrDefault(f.ReportsPerDay, def.ReportsPerDay),
	}
}

func intOrDefault(fv, def int) int {
	if fv == 0 {
		return def
	}
	return fv
}

func ruleOrDefault(fr fileRule, def ratelimit.Rule) ratelimit.Rule {
	if fr.N == 0 && fr.Per == "" {
		return def
	}
	per, err := time.ParseDuration(fr.Per)
	if err != nil || fr.N <= 0 || per <= 0 {
		return def
	}
	return ratelimit.Rule{N: fr.N, Per: per}
}

// readFile loads $CONFIG_FILE (must exist) or ./config.yaml (optional).
func readFile() (file, error) {
	path, explicit := os.Getenv("CONFIG_FILE"), true
	if path == "" {
		path, explicit = defaultFile, false
	}
	raw, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) && !explicit {
		return file{}, nil
	}
	if err != nil {
		return file{}, fmt.Errorf("config file: %w", err)
	}
	var f file
	dec := yaml.NewDecoder(bytes.NewReader(raw))
	dec.KnownFields(true) // a typo in a key is an error, not a silent default
	if err := dec.Decode(&f); err != nil && !errors.Is(err, io.EOF) {
		return file{}, fmt.Errorf("config file %s: %w", path, err)
	}
	return f, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getenvInt64(key string, fileVal, def int64) int64 {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	if fileVal != 0 {
		return fileVal
	}
	return def
}

func getenvInt(key string, fileVal, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	if fileVal != 0 {
		return fileVal
	}
	return def
}

func or(v, def string) string {
	if v != "" {
		return v
	}
	return def
}

func orInt(v, def int) int {
	if v != 0 {
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
