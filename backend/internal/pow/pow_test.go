package pow

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestNewChallenge(t *testing.T) {
	c := NewChallenge("register", 20)
	if c.Resource != "register" {
		t.Fatal("wrong resource")
	}
	if c.Difficulty != 20 {
		t.Fatal("wrong difficulty")
	}
	if c.Salt == "" {
		t.Fatal("empty salt")
	}
	if time.Now().Unix()-c.Created > 1 {
		t.Fatal("wrong timestamp")
	}
}

func TestChallengeString(t *testing.T) {
	c := NewChallenge("register", 20)
	s := c.String()
	parts := strings.Split(s, ":")
	if len(parts) != 6 {
		t.Fatalf("expected 6 parts, got %d: %s", len(parts), s)
	}
}

func TestParseChallenge(t *testing.T) {
	c := NewChallenge("register", 20)
	s := c.String()
	parsed, err := ParseChallenge(s)
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if parsed.Resource != c.Resource || parsed.Difficulty != c.Difficulty {
		t.Fatal("parsed challenge doesn't match")
	}
}

func TestVerifyValidSolution(t *testing.T) {
	c := NewChallenge("register", 16) // Low difficulty for testing
	// ~65k tries on average; a tight cap made this fail about 1 run in 5.
	nonce := c.Solve(10_000_000)
	if nonce == "" {
		t.Fatal("could not solve challenge")
	}
	sol := &Solution{Challenge: c.String(), Nonce: nonce}
	if !c.Verify(sol) {
		t.Fatal("valid solution rejected")
	}
}

func TestVerifyInvalidSolution(t *testing.T) {
	c := NewChallenge("register", 20)
	sol := &Solution{Challenge: c.String(), Nonce: "invalid"}
	if c.Verify(sol) {
		t.Fatal("invalid solution accepted")
	}
}

func TestVerifyWrongChallenge(t *testing.T) {
	c1 := NewChallenge("register", 12)
	c2 := NewChallenge("login", 12)
	nonce := c1.Solve(100000)
	if nonce == "" {
		t.Fatal("could not solve challenge")
	}
	sol := &Solution{Challenge: c2.String(), Nonce: nonce}
	if c2.Verify(sol) {
		t.Fatal("solution for wrong challenge accepted")
	}
}
func solveToken(t *testing.T, token string, difficulty int) string {
	t.Helper()
	for i := 0; i < 50_000_000; i++ {
		nonce := fmt.Sprintf("%x", i)
		h := sha256.Sum256([]byte(token + ":" + nonce))
		if leadingZeroBits(h[:]) >= difficulty {
			return nonce
		}
	}
	t.Fatal("could not solve token")
	return ""
}

func TestIssuerAcceptsSolutionOnce(t *testing.T) {
	iss := NewIssuer([]byte("secret"), "register", 12)
	tok := iss.Issue()
	nonce := solveToken(t, tok, 12)
	if err := iss.Check(tok, nonce); err != nil {
		t.Fatalf("valid solution rejected: %v", err)
	}
	if err := iss.Check(tok, nonce); err == nil {
		t.Fatal("replayed solution accepted")
	}
}

func TestIssuerRejectsForgedToken(t *testing.T) {
	iss := NewIssuer([]byte("secret"), "register", 12)
	// Self-made easy challenge signed with another key.
	forged := NewIssuer([]byte("other"), "register", 1).Issue()
	if err := iss.Check(forged, solveToken(t, forged, 1)); err == nil {
		t.Fatal("forged token accepted")
	}
	tok := iss.Issue()
	if err := iss.Check(tok, "nope"); err == nil {
		t.Fatal("wrong nonce accepted")
	}
}

func TestIssuerRejectsExpired(t *testing.T) {
	iss := NewIssuer([]byte("secret"), "register", 1)
	c := NewChallenge("register", 1)
	c.Created -= int64(c.MaxAge) + 1
	tok := c.String() + ":" + iss.sign(c.String())
	if err := iss.Check(tok, solveToken(t, tok, 1)); err != ErrExpired {
		t.Fatalf("err = %v, want ErrExpired", err)
	}
}
