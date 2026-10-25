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
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/go-sql-driver/mysql"
	"gopkg.in/yaml.v3"
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
	// AllowedOrigins are the browser origins (e.g. "https://devilapi.github.io")
	// the web app may call this API from (CORS). Empty: no cross-origin access.
	AllowedOrigins []string
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
	Database       database `yaml:"database"`
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

// Load reads the configuration and requires a JWT secret (the API server).
func Load() (Config, error) {
	c, err := Read()
	if err != nil {
		return Config{}, err
	}
	if len(c.JWTSecret) == 0 {
		return Config{}, errors.New("JWT_SECRET must be set (env or jwt_secret in the config file)")
	}
	return c, nil
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
	return Config{
		DatabaseURL:    getenv("DATABASE_URL", or(f.Database.dsn(), defaultDatabaseURL)),
		JWTSecret:      []byte(getenv("JWT_SECRET", f.JWTSecret)),
		UploadDir:      getenv("UPLOAD_DIR", or(f.UploadDir, "./uploads")),
		Addr:           getenv("ADDR", or(f.Addr, ":8080")),
		MigrationsDir:  getenv("MIGRATIONS_DIR", or(f.MigrationsDir, "migrations")),
		PublicBaseURL:  strings.TrimRight(getenv("PUBLIC_BASE_URL", or(f.PublicBaseURL, "http://localhost:8080")), "/"),
		GeocoderURL:    getenv("GEOCODER_URL", or(f.GeocoderURL, "https://nominatim.openstreetmap.org")),
		AllowedOrigins: origins,
	}, nil
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
