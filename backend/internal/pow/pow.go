// Package pow provides a simple proof-of-work (Hashcash) for registration abuse prevention.
package pow

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/bits"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Challenge represents a proof-of-work challenge.
type Challenge struct {
	// Version of the PoW algorithm (for future upgrades)
	Version int `json:"version"`
	// Resource being protected (e.g., "register")
	Resource string `json:"resource"`
	// Random salt to prevent precomputation
	Salt string `json:"salt"`
	// Difficulty: number of leading zero bits required in the hash
	Difficulty int `json:"difficulty"`
	// Timestamp when the challenge was created (Unix time)
	Created int64 `json:"created"`
	// Max age of the challenge in seconds (default 10 minutes)
	MaxAge int `json:"max_age"`
}

// NewChallenge creates a new proof-of-work challenge.
func NewChallenge(resource string, difficulty int) *Challenge {
	salt := make([]byte, 16)
	_, _ = rand.Read(salt)
	return &Challenge{
		Version:    1,
		Resource:   resource,
		Salt:       hex.EncodeToString(salt),
		Difficulty: difficulty,
		Created:    time.Now().Unix(),
		MaxAge:     600, // 10 minutes
	}
}

// String returns the challenge as a string for client-side solving.
func (c *Challenge) String() string {
	return fmt.Sprintf("%d:%s:%s:%d:%d:%d", c.Version, c.Resource, c.Salt, c.Difficulty, c.Created, c.MaxAge)
}

// ParseChallenge parses a challenge string.
func ParseChallenge(s string) (*Challenge, error) {
	parts := strings.Split(s, ":")
	if len(parts) != 6 {
		return nil, fmt.Errorf("invalid challenge format")
	}
	version, _ := strconv.Atoi(parts[0])
	difficulty, _ := strconv.Atoi(parts[3])
	created, _ := strconv.ParseInt(parts[4], 10, 64)
	maxAge, _ := strconv.Atoi(parts[5])
	return &Challenge{
		Version:    version,
		Resource:   parts[1],
		Salt:       parts[2],
		Difficulty: difficulty,
		Created:    created,
		MaxAge:     maxAge,
	}, nil
}

// Solution represents a proof-of-work solution.
type Solution struct {
	Challenge string `json:"challenge"`
	Nonce     string `json:"nonce"`
}

// Verify checks if the solution is valid for the given challenge.
func (c *Challenge) Verify(sol *Solution) bool {
	// Check challenge matches
	if sol.Challenge != c.String() {
		return false
	}
	// Check max age
	if time.Now().Unix()-c.Created > int64(c.MaxAge) {
		return false
	}
	// Compute hash
	data := c.String() + ":" + sol.Nonce
	hash := sha256.Sum256([]byte(data))
	// Count leading zero bits
	leadingZeros := 0
	for _, b := range hash {
		if b == 0 {
			leadingZeros += 8
		} else {
			for i := 7; i >= 0; i-- {
				if (b>>i)&1 == 0 {
					leadingZeros++
				} else {
					break
				}
			}
			break
		}
	}
	return leadingZeros >= c.Difficulty
}

// Solve attempts to find a valid nonce for the challenge.
// This is meant for testing; in production the client solves it.
func (c *Challenge) Solve(maxIterations int) string {
	for i := 0; i < maxIterations; i++ {
		nonce := fmt.Sprintf("%x", i)
		sol := &Solution{Challenge: c.String(), Nonce: nonce}
		if c.Verify(sol) {
			return nonce
		}
	}
	return ""
}

// Issuer hands out signed challenges and checks solutions to them without
// keeping state per challenge, except for the salts already used.
type Issuer struct {
	secret     []byte
	resource   string
	difficulty int

	mu   sync.Mutex
	used map[string]int64 // salt -> expiry (Unix time)
}

// NewIssuer returns an issuer whose challenges are signed with secret.
func NewIssuer(secret []byte, resource string, difficulty int) *Issuer {
	return &Issuer{secret: secret, resource: resource, difficulty: difficulty, used: map[string]int64{}}
}

// Errors returned by Issuer.Check.
var (
	ErrInvalid = errors.New("invalid proof-of-work")
	ErrExpired = errors.New("proof-of-work challenge expired")
)

// Issue returns a fresh challenge token: the challenge string followed by
// ":" and its HMAC. The client finds a nonce such that
// SHA-256(token + ":" + nonce) has Difficulty leading zero bits.
func (i *Issuer) Issue() string {
	c := NewChallenge(i.resource, i.difficulty).String()
	return c + ":" + i.sign(c)
}

func (i *Issuer) sign(c string) string {
	m := hmac.New(sha256.New, i.secret)
	m.Write([]byte(c))
	return hex.EncodeToString(m.Sum(nil))
}

// Check verifies a solution for a token from Issue. Each token is accepted
// once.
func (i *Issuer) Check(token, nonce string) error {
	cut := strings.LastIndexByte(token, ':')
	if cut < 0 || nonce == "" || len(nonce) > 64 {
		return ErrInvalid
	}
	cs, sig := token[:cut], token[cut+1:]
	if !hmac.Equal([]byte(sig), []byte(i.sign(cs))) {
		return ErrInvalid
	}
	c, err := ParseChallenge(cs)
	if err != nil || c.Resource != i.resource || c.Difficulty < i.difficulty {
		return ErrInvalid
	}
	now := time.Now().Unix()
	if now-c.Created > int64(c.MaxAge) {
		return ErrExpired
	}
	hash := sha256.Sum256([]byte(token + ":" + nonce))
	if leadingZeroBits(hash[:]) < c.Difficulty {
		return ErrInvalid
	}
	i.mu.Lock()
	defer i.mu.Unlock()
	for s, exp := range i.used {
		if exp < now {
			delete(i.used, s)
		}
	}
	if _, seen := i.used[c.Salt]; seen {
		return ErrInvalid
	}
	i.used[c.Salt] = c.Created + int64(c.MaxAge)
	return nil
}

func leadingZeroBits(b []byte) int {
	n := 0
	for _, x := range b {
		if x == 0 {
			n += 8
			continue
		}
		return n + bits.LeadingZeros8(x)
	}
	return n
}
