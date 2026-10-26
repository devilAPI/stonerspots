package pow

import (
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