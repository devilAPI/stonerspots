package config

import (
	"strings"
	"testing"
	"time"

	"stonerspots/backend/internal/ratelimit"
)

var securityEnvKeys = []string{
	"MAIL_HOST", "MAIL_PORT", "MAIL_USERNAME", "MAIL_PASSWORD", "MAIL_FROM",
	"APP_BASE_URL", "POW_DIFFICULTY", "REQUIRE_ADMIN_TOTP",
}

func clearSecurityEnv(t *testing.T) {
	clearEnv(t)
	for _, k := range securityEnvKeys {
		t.Setenv(k, "")
	}
}

func TestSecurityKeysFromFile(t *testing.T) {
	clearSecurityEnv(t)
	t.Setenv("CONFIG_FILE", writeFile(t, `
jwt_secret: `+strongSecret+`
public_base_url: https://api.example.org
app_base_url: https://devilapi.github.io/stonerspots/#/
pow_difficulty: 21
require_admin_totp: true
limits:
  forgot_password: { n: 4, per: "1h" }
  forgot_password_email: { n: 1, per: "30m" }
  search: { n: 30, per: "1m" }
  follows_per_day: 50
  likes_per_day: 70
`))
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.AppBaseURL != "https://devilapi.github.io/stonerspots/#" || c.PowDifficulty != 21 || !c.RequireAdminTOTP {
		t.Fatalf("config = %+v", c)
	}
	l := c.Limits
	if l.ForgotPassword != (ratelimit.Rule{N: 4, Per: time.Hour}) ||
		l.ForgotPasswordEmail != (ratelimit.Rule{N: 1, Per: 30 * time.Minute}) ||
		l.Search != (ratelimit.Rule{N: 30, Per: time.Minute}) ||
		l.FollowsPerDay != 50 || l.LikesPerDay != 70 {
		t.Fatalf("limits = %+v", l)
	}
	t.Setenv("POW_DIFFICULTY", "19")
	t.Setenv("REQUIRE_ADMIN_TOTP", "false")
	t.Setenv("APP_BASE_URL", "https://app.example.net/")
	if c, err = Load(); err != nil {
		t.Fatal(err)
	}
	if c.PowDifficulty != 19 || c.RequireAdminTOTP || c.AppBaseURL != "https://app.example.net" {
		t.Fatalf("env overrides: %+v", c)
	}
}

func TestSecurityDefaults(t *testing.T) {
	clearSecurityEnv(t)
	t.Chdir(t.TempDir())
	t.Setenv("JWT_SECRET", strongSecret)
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.PowDifficulty != DefaultPowDifficulty || c.RequireAdminTOTP || c.AppBaseURL != "" {
		t.Fatalf("config = %+v", c)
	}
	def := DefaultLimits()
	if c.Limits.ForgotPassword != def.ForgotPassword || c.Limits.Search != def.Search ||
		def.ForgotPasswordEmail.N != 3 || def.FollowsPerDay != 200 || def.LikesPerDay != 300 {
		t.Fatalf("limits = %+v", c.Limits)
	}
}

func TestPowDifficultyRange(t *testing.T) {
	for _, v := range []string{"0x", "40", "-1"} {
		clearSecurityEnv(t)
		t.Chdir(t.TempDir())
		t.Setenv("JWT_SECRET", strongSecret)
		t.Setenv("POW_DIFFICULTY", v)
		_, err := Load()
		if v == "0x" { // not a number: the default applies
			if err != nil {
				t.Fatalf("%s: %v", v, err)
			}
			continue
		}
		if err == nil || !strings.Contains(err.Error(), "pow_difficulty") {
			t.Fatalf("%s: err = %v", v, err)
		}
	}
}

// With mail on, a public server needs app_base_url: the mail links would
// lead nowhere and new users could never verify their address.
func TestMailNeedsAppBaseURL(t *testing.T) {
	for name, tc := range map[string]struct{ app, public, want string }{
		"unset":           {"", "https://api.stonerspots.de", "is not set"},
		"example.com":     {"https://example.com", "https://api.stonerspots.de", "example value"},
		"not a URL":       {"devilapi.github.io", "https://api.stonerspots.de", "http(s) URL"},
		"good":            {"https://devilapi.github.io/stonerspots/#", "https://api.stonerspots.de", ""},
		"unset but local": {"", "http://localhost:8080", ""},
	} {
		t.Run(name, func(t *testing.T) {
			clearSecurityEnv(t)
			t.Chdir(t.TempDir())
			t.Setenv("JWT_SECRET", strongSecret)
			t.Setenv("PUBLIC_BASE_URL", tc.public)
			t.Setenv("MAIL_HOST", "smtp.stonerspots.de")
			t.Setenv("MAIL_FROM", "noreply@stonerspots.de")
			t.Setenv("APP_BASE_URL", tc.app)
			_, err := Load()
			if tc.want == "" {
				if err != nil {
					t.Fatal(err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want %q", err, tc.want)
			}
		})
	}
	// without mail the URL is not needed
	clearSecurityEnv(t)
	t.Chdir(t.TempDir())
	t.Setenv("JWT_SECRET", strongSecret)
	t.Setenv("PUBLIC_BASE_URL", "https://api.stonerspots.de")
	if _, err := Load(); err != nil {
		t.Fatal(err)
	}
}
