// Package totp provides TOTP (RFC 6238) for admin two-factor authentication.
package totp

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// GenerateSecret returns a new random base32-encoded secret (20 bytes = 160 bits).
func GenerateSecret() (string, error) {
	b := make([]byte, 20)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b), nil
}

// Validate checks if the provided code is valid for the given secret at the current time.
// It accepts codes from the current and previous time step (skew tolerance).
func Validate(secret, code string) bool {
	_, ok := Match(secret, code, time.Now())
	return ok
}

// Step is the length of one TOTP time step.
const Step = 30 * time.Second

// Match reports whether code is valid at now, accepting the previous,
// current and next 30 s step for clock skew, and returns the step it
// belongs to (Unix time / 30), so callers can accept every step only once.
func Match(secret, code string, now time.Time) (int64, bool) {
	key, ok := decodeSecret(secret)
	if !ok || len(code) != 6 {
		return 0, false
	}
	cur := now.Unix() / int64(Step/time.Second)
	for i := int64(-1); i <= 1; i++ {
		if subtle.ConstantTimeCompare([]byte(hotp(key, cur+i)), []byte(code)) == 1 {
			return cur + i, true
		}
	}
	return 0, false
}

// Code returns the code for the time step containing t (what an
// authenticator app shows at t; for tests).
func Code(secret string, t time.Time) string {
	key, ok := decodeSecret(secret)
	if !ok {
		return ""
	}
	return hotp(key, t.Unix()/int64(Step/time.Second))
}

func decodeSecret(secret string) ([]byte, bool) {
	secret = strings.ToUpper(strings.ReplaceAll(secret, " ", ""))
	key, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(secret)
	return key, err == nil && len(key) > 0
}

func hotp(key []byte, counter int64) string {
	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, uint64(counter))
	mac := hmac.New(sha1.New, key)
	mac.Write(buf)
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	truncated := binary.BigEndian.Uint32(sum[offset : offset+4])
	truncated &= 0x7fffffff
	return fmt.Sprintf("%06d", truncated%1000000)
}

// ProvisioningURI returns an otpauth:// URI for QR code generation.
func ProvisioningURI(secret, account, issuer string) string {
	params := url.Values{}
	params.Set("secret", secret)
	if issuer != "" {
		params.Set("issuer", issuer)
	}
	return "otpauth://totp/" + url.PathEscape(issuer+":"+account) + "?" + params.Encode()
}