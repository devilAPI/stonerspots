package config

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"stonerspots/backend/internal/ratelimit"
)

func TestLegalFromFile(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", writeFile(t, `
legal:
  operator_name: " Erika Beispiel "
  address: |
    c/o Adressdienst
    Weg 2
    10115 Berlin
  email: erika@beispiel.test
  phone: "+49 30 0"
  country: Deutschland
  extra: Hobbyprojekt
`))
	c, err := Read()
	if err != nil {
		t.Fatal(err)
	}
	l := c.Legal
	if l.OperatorName != "Erika Beispiel" || l.Address != "c/o Adressdienst\nWeg 2\n10115 Berlin" ||
		l.Email != "erika@beispiel.test" || l.Phone != "+49 30 0" || l.Country != "Deutschland" || l.Extra != "Hobbyprojekt" {
		t.Fatalf("legal = %+v", l)
	}
	if !l.Configured() {
		t.Fatal("name, address and email set: configured")
	}
	d := l.WithDefaults()
	if d.ResponsiblePerson != "Erika Beispiel" || d.PrivacyContactEmail != "erika@beispiel.test" {
		t.Fatalf("defaults = %+v", d)
	}
}

func TestLegalEnvOverrides(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", writeFile(t, `
legal:
  operator_name: File Name
  email: file@beispiel.test
`))
	t.Setenv("LEGAL_OPERATOR_NAME", "Env Name")
	t.Setenv("LEGAL_ADDRESS", `c/o Service\nStraße 1\n12345 Ort`)
	t.Setenv("LEGAL_RESPONSIBLE_PERSON", "Verantwortliche Person")
	t.Setenv("LEGAL_PRIVACY_CONTACT_EMAIL", "privacy@beispiel.test")
	c, err := Read()
	if err != nil {
		t.Fatal(err)
	}
	l := c.Legal.WithDefaults()
	if l.OperatorName != "Env Name" || l.Address != "c/o Service\nStraße 1\n12345 Ort" || l.Email != "file@beispiel.test" {
		t.Fatalf("legal = %+v", l)
	}
	if l.ResponsiblePerson != "Verantwortliche Person" || l.PrivacyContactEmail != "privacy@beispiel.test" {
		t.Fatalf("explicit values must win over defaults: %+v", l)
	}
}

func TestLegalConfigured(t *testing.T) {
	full := LegalConfig{OperatorName: "A", Address: "B\nC", Email: "a@beispiel.test"}
	for name, tc := range map[string]struct {
		l    LegalConfig
		want bool
	}{
		"complete":            {full, true},
		"nothing":             {LegalConfig{}, false},
		"no name":             {LegalConfig{Address: "B", Email: "a@beispiel.test"}, false},
		"no address":          {LegalConfig{OperatorName: "A", Email: "a@beispiel.test"}, false},
		"blank address":       {LegalConfig{OperatorName: "A", Address: "  ", Email: "a@beispiel.test"}, false},
		"no email":            {LegalConfig{OperatorName: "A", Address: "B"}, false},
		"example email":       {LegalConfig{OperatorName: "A", Address: "B", Email: "kontakt@example.org"}, false},
		"example subdomain":   {LegalConfig{OperatorName: "A", Address: "B", Email: "k@mail.example.com"}, false},
		"example privacy box": {LegalConfig{OperatorName: "A", Address: "B", Email: "a@beispiel.test", PrivacyContactEmail: "d@example.net"}, false},
		"lookalike domain":    {LegalConfig{OperatorName: "A", Address: "B", Email: "a@myexample.org"}, true},
	} {
		t.Run(name, func(t *testing.T) {
			if got := tc.l.Configured(); got != tc.want {
				t.Fatalf("Configured() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestLegalWarning(t *testing.T) {
	set := LegalConfig{OperatorName: "A", Address: "B", Email: "a@beispiel.test"}
	if w := legalWarning(Config{PublicBaseURL: "http://localhost:8080"}); w != "" {
		t.Fatalf("local development needs no legal notice: %q", w)
	}
	if w := legalWarning(Config{PublicBaseURL: "https://api.beispiel.test"}); !strings.Contains(w, "legal") || !strings.Contains(w, "c/o") {
		t.Fatalf("public server without details: %q", w)
	}
	if w := legalWarning(Config{PublicBaseURL: "https://api.beispiel.test", Legal: set}); w != "" {
		t.Fatalf("configured: %q", w)
	}
}

// The example's legal section is empty: copying it must not publish
// placeholder details as a legal notice.
func TestExampleFileLegalUnset(t *testing.T) {
	clearEnv(t)
	t.Setenv("CONFIG_FILE", filepath.Join("..", "..", "config.example.yaml"))
	c, err := Read()
	if err != nil {
		t.Fatal(err)
	}
	if c.Legal.Configured() || c.Legal.OperatorName != "" {
		t.Fatalf("legal = %+v", c.Legal)
	}
	if c.Limits.Exports != (ratelimit.Rule{N: 3, Per: 24 * time.Hour}) {
		t.Fatalf("exports limit = %+v", c.Limits.Exports)
	}
}
