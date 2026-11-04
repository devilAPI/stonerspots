// Package hibp checks passwords against the Have I Been Pwned k-anonymity API.
// See https://haveibeenpwned.com/API/v3#PwnedPasswords
package hibp

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// PrefixLen is how many hex characters of the SHA-1 hash are sent: the
// range API takes exactly 5 and answers 400 to anything else.
const PrefixLen = 5

const (
	defaultAPI = "https://api.pwnedpasswords.com/range/"
	timeout    = 5 * time.Second
)

// Client checks passwords against HIBP.
type Client struct {
	httpClient *http.Client
	baseURL    string
}

// NewClient returns a client for the HIBP API.
func NewClient() *Client {
	return &Client{
		httpClient: &http.Client{Timeout: timeout},
		baseURL:    defaultAPI,
	}
}

// NewClientAt returns a client for an HIBP-compatible range API at baseURL
// (ending in "/range/"; tests point it at a fake).
func NewClientAt(baseURL string) *Client {
	c := NewClient()
	c.baseURL = baseURL
	return c
}

// IsBreached reports whether the password appears in known breaches.
// It returns (breached, error). A network error returns false with the error.
func (c *Client) IsBreached(ctx context.Context, password string) (bool, error) {
	sum := sha1.Sum([]byte(password))
	hash := strings.ToUpper(hex.EncodeToString(sum[:]))
	// Only the first 5 hex characters (20 bits) leave the server; the API
	// answers with every suffix under that prefix (k-anonymity).
	prefix, suffix := hash[:PrefixLen], hash[PrefixLen:]

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+prefix, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("User-Agent", "Stonerspots/1.0")
	req.Header.Set("Add-Padding", "true")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("hibp: status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, err
	}

	lines := strings.Split(string(body), "\n")
	for _, line := range lines {
		parts := strings.Split(line, ":")
		if len(parts) == 2 && strings.EqualFold(parts[0], suffix) {
			return true, nil
		}
	}
	return false, nil
}