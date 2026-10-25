// Package totp provides TOTP (RFC 6238) for admin two-factor authentication.
package totp

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
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
	secret = strings.ToUpper(strings.ReplaceAll(secret, " ", ""))
	key, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(secret)
	if err != nil {
		return false
	}
	now := time.Now().Unix() / 30
	for i := -1; i <= 1; i++ {
		if hotp(key, now+int64(i)) == code {
			return true
		}
	}
	return false
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