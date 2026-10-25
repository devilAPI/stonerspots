package ratelimit

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

type clock struct{ t time.Time }

func (c *clock) now() time.Time      { return c.t }
func (c *clock) add(d time.Duration) { c.t = c.t.Add(d) }
func newAt(r Rule) (*Limiter, *clock) {
	c := &clock{t: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	l := New(r)
	l.now = c.now
	return l, c
}

func TestBurstThenRefill(t *testing.T) {
	l, c := newAt(Rule{N: 3, Per: time.Minute})
	for i := 0; i < 3; i++ {
		if ok, _ := l.Allow("a"); !ok {
			t.Fatalf("request %d of the burst refused", i)
		}
	}
	ok, retry := l.Allow("a")
	if ok || retry != 20*time.Second {
		t.Fatalf("4th: ok=%v retry=%v, want refused for 20s", ok, retry)
	}
	// other keys are independent
	if ok, _ := l.Allow("b"); !ok {
		t.Fatal("b refused")
	}
	c.add(20 * time.Second) // one token back
	if ok, _ := l.Allow("a"); !ok {
		t.Fatal("refill")
	}
	if ok, _ := l.Allow("a"); ok {
		t.Fatal("only one token came back")
	}
	c.add(time.Hour) // never more than the burst
	for i := 0; i < 3; i++ {
		l.Allow("a")
	}
	if ok, _ := l.Allow("a"); ok {
		t.Fatal("burst exceeded after a long pause")
	}
}

func TestBlockedDoesNotConsume(t *testing.T) {
	l, _ := newAt(Rule{N: 2, Per: time.Hour})
	for i := 0; i < 5; i++ {
		if b, _ := l.Blocked("k"); b {
			t.Fatal("peeking must not use tokens")
		}
	}
	l.Allow("k")
	l.Allow("k")
	if b, retry := l.Blocked("k"); !b || retry != 30*time.Minute {
		t.Fatalf("blocked=%v retry=%v", b, retry)
	}
}

func TestOffRuleAndNilLimiterAllowAll(t *testing.T) {
	if New(Rule{}) != nil || New(Rule{N: 5}) != nil {
		t.Fatal("zero rules must give a nil limiter")
	}
	var l *Limiter
	if ok, _ := l.Allow("x"); !ok {
		t.Fatal("nil Allow")
	}
	if b, _ := l.Blocked("x"); b {
		t.Fatal("nil Blocked")
	}
	h := Middleware(nil, func(*http.Request) string { return "x" })(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(204)
	}))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/", nil))
	if w.Code != 204 {
		t.Fatal(w.Code)
	}
}

func TestMemoryIsBounded(t *testing.T) {
	l, c := newAt(Rule{N: 1, Per: time.Minute})
	for i := 0; i < maxKeys+10; i++ {
		l.Allow(fmt.Sprint(i))
	}
	if n := len(l.buckets); n > maxKeys {
		t.Fatalf("%d buckets", n)
	}
	// idle buckets go first
	c.add(2 * time.Minute)
	l.sweep(c.now())
	if n := len(l.buckets); n != 0 {
		t.Fatalf("%d idle buckets kept", n)
	}
}

func TestMiddlewareAnswers429(t *testing.T) {
	l, _ := newAt(Rule{N: 1, Per: time.Minute})
	h := ByIP(l)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(204)
	}))
	call := func() *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", "/", nil))
		return w
	}
	if w := call(); w.Code != 204 {
		t.Fatal(w.Code)
	}
	w := call()
	if w.Code != 429 || w.Header().Get("Retry-After") != "60" {
		t.Fatalf("%d %q %s", w.Code, w.Header().Get("Retry-After"), w.Body)
	}
}
