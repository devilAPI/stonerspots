package totp

import (
	"encoding/base32"
	"strings"
	"testing"
	"time"
)

func TestGenerateSecret(t *testing.T) {
	s1, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	if s1 == "" {
		t.Fatal("empty secret")
	}
	s2, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	if s1 == s2 {
		t.Fatal("secrets should be unique")
	}
}

func TestValidate(t *testing.T) {
	secret := "JBSWY3DPEHPK3PXP" // RFC 6238 test vector
	// Can't test exact code without knowing time, but we can test round-trip
	code := hotp(decodeBase32(secret), time.Now().Unix()/30)
	if !Validate(secret, code) {
		t.Fatal("valid code rejected")
	}
	if Validate(secret, "000000") {
		t.Fatal("invalid code accepted")
	}
}

func TestValidateCaseInsensitive(t *testing.T) {
	secret := "jbswY3dpehpK3pxP"
	code := hotp(decodeBase32(strings.ToUpper(secret)), time.Now().Unix()/30)
	if !Validate(secret, code) {
		t.Fatal("case insensitive validation failed")
	}
}

func TestValidateWithSpaces(t *testing.T) {
	secret := "JBSW Y3DP EHPK 3PXP"
	code := hotp(decodeBase32(strings.ReplaceAll(secret, " ", "")), time.Now().Unix()/30)
	if !Validate(secret, code) {
		t.Fatal("space-tolerant validation failed")
	}
}

func decodeBase32(s string) []byte {
	b, _ := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(s)
	return b
}