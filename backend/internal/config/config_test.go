package config

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/go-sql-driver/mysql"
)

var envKeys = []string{
	"CONFIG_FILE", "DATABASE_URL", "JWT_SECRET", "UPLOAD_DIR", "ADDR", "PUBLIC_BASE_URL",
	"GEOCODER_URL", "ALLOWED_ORIGINS", "MIGRATIONS_DIR",
}

// clearEnv blanks every variable Load reads; getenv treats "" as unset.
func clearEnv(t *testing.T) {
	for _, k := range envKeys {
		t.Setenv(k, "")
	}
}

func writeFile(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadFromFile(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", writeFile(t, `
addr: ":9000"
public_base_url: https://api.example.com/
allowed_origins: [https://devilapi.github.io]
jwt_secret: file-secret
upload_dir: /srv/uploads
migrations_dir: /srv/migrations
database:
  host: db.internal
  port: 3306
  user: app
  password: "p@ss:w/rd"
  name: spots
`))
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.Addr != ":9000" || string(c.JWTSecret) != "file-secret" || c.UploadDir != "/srv/uploads" ||
		c.MigrationsDir != "/srv/migrations" || c.PublicBaseURL != "https://api.example.com" {
		t.Fatalf("config = %+v", c)
	}
	if !reflect.DeepEqual(c.AllowedOrigins, []string{"https://devilapi.github.io"}) {
		t.Fatalf("origins = %v", c.AllowedOrigins)
	}
	dsn, err := mysql.ParseDSN(c.DatabaseURL)
	if err != nil {
		t.Fatalf("dsn %q: %v", c.DatabaseURL, err)
	}
	if dsn.Addr != "db.internal:3306" || dsn.User != "app" || dsn.Passwd != "p@ss:w/rd" ||
		dsn.DBName != "spots" || !dsn.ParseTime || !dsn.MultiStatements {
		t.Fatalf("dsn = %+v", dsn)
	}
}

func TestEnvOverridesFile(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", writeFile(t, "jwt_secret: file-secret\naddr: \":9000\"\n"))
	t.Setenv("JWT_SECRET", "env-secret")
	t.Setenv("DATABASE_URL", "u:p@tcp(h:1)/d")
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if string(c.JWTSecret) != "env-secret" || c.DatabaseURL != "u:p@tcp(h:1)/d" || c.Addr != ":9000" {
		t.Fatalf("config = %+v", c)
	}
}

func TestDatabaseURLInFileWins(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", writeFile(t, "jwt_secret: x\ndatabase:\n  url: \"u:p@tcp(h:1)/d\"\n  host: ignored\n"))
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.DatabaseURL != "u:p@tcp(h:1)/d" {
		t.Fatalf("dsn = %q", c.DatabaseURL)
	}
}

func TestDefaultsWithoutFile(t *testing.T) {
	clearEnv(t)
	t.Chdir(t.TempDir()) // no config.yaml here
	t.Setenv("JWT_SECRET", "s")
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.DatabaseURL != defaultDatabaseURL || c.Addr != ":8080" || c.MigrationsDir != "migrations" {
		t.Fatalf("config = %+v", c)
	}
}

func TestDefaultFileInWorkingDir(t *testing.T) {
	clearEnv(t)
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte("jwt_secret: from-cwd\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Chdir(dir)
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if string(c.JWTSecret) != "from-cwd" {
		t.Fatalf("secret = %q", c.JWTSecret)
	}
}

func TestErrors(t *testing.T) {
	for name, tc := range map[string]struct{ file, want string }{
		"missing explicit file": {"", "no such file"},
		"unknown key":           {"jwt_secret: x\ndatabse: {}\n", "databse"},
		"no jwt secret":         {"addr: \":1\"\n", "JWT_SECRET"},
	} {
		t.Run(name, func(t *testing.T) {
			clearEnv(t)
			p := filepath.Join(t.TempDir(), "missing.yaml")
			if tc.file != "" {
				p = writeFile(t, tc.file)
			}
			t.Setenv("CONFIG_FILE", p)
			_, err := Load()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want it to mention %q", err, tc.want)
			}
		})
	}
}

func TestReadSkipsSecretCheck(t *testing.T) {
	clearEnv(t)
	t.Chdir(t.TempDir())
	if _, err := Read(); err != nil {
		t.Fatal(err)
	}
}

func TestExampleFileParses(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", filepath.Join("..", "..", "config.example.yaml"))
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.DatabaseURL == "" || len(c.AllowedOrigins) != 1 {
		t.Fatalf("config = %+v", c)
	}
}
