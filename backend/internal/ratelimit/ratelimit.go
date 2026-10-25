// Package ratelimit holds in-memory token-bucket limiters keyed by client
// (IP, user id, email). They live in one API process; behind several
// processes each one limits on its own.
package ratelimit

import (
	"net/http"
	"strconv"
	"sync"
	"time"

	"stonerspots/backend/internal/httpx"
)

// Rule allows N events per Per, in bursts of up to N. A zero Rule allows
// everything.
type Rule struct {
	N   int
	Per time.Duration
}

// Off reports whether the rule limits nothing.
func (r Rule) Off() bool { return r.N <= 0 || r.Per <= 0 }

// maxKeys bounds memory: past it, idle buckets are dropped, and if that is
// not enough the oldest-looking half goes (those clients start fresh).
const maxKeys = 100_000

type bucket struct {
	tokens float64
	last   time.Time
}

// Limiter is a set of token buckets, one per key.
type Limiter struct {
	rule Rule
	now  func() time.Time

	mu      sync.Mutex
	buckets map[string]*bucket
}

// New returns a limiter for rule (nil for an Off rule, which allows all).
func New(rule Rule) *Limiter {
	if rule.Off() {
		return nil
	}
	return &Limiter{rule: rule, now: time.Now, buckets: map[string]*bucket{}}
}

// refill brings b up to date and returns it; callers hold mu.
func (l *Limiter) refill(key string, now time.Time) *bucket {
	b := l.buckets[key]
	if b == nil {
		if len(l.buckets) >= maxKeys {
			l.sweep(now)
		}
		b = &bucket{tokens: float64(l.rule.N), last: now}
		l.buckets[key] = b
		return b
	}
	rate := float64(l.rule.N) / l.rule.Per.Seconds()
	b.tokens = min(float64(l.rule.N), b.tokens+now.Sub(b.last).Seconds()*rate)
	b.last = now
	return b
}

// sweep drops full (idle) buckets, then half of the rest if still too many.
func (l *Limiter) sweep(now time.Time) {
	for k, b := range l.buckets {
		if now.Sub(b.last) >= l.rule.Per {
			delete(l.buckets, k)
		}
	}
	if len(l.buckets) < maxKeys {
		return
	}
	n := 0
	for k := range l.buckets {
		if n%2 == 0 {
			delete(l.buckets, k)
		}
		n++
	}
}

// Allow takes one token for key. When none is left it reports false and how
// long until the next one. A nil Limiter allows everything.
func (l *Limiter) Allow(key string) (bool, time.Duration) {
	if l == nil {
		return true, 0
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	b := l.refill(key, now)
	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	return false, l.wait(b)
}

// Blocked reports whether key has no token left, without taking one (for
// limits that only count failures, like wrong passwords).
func (l *Limiter) Blocked(key string) (bool, time.Duration) {
	if l == nil {
		return false, 0
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.refill(key, l.now())
	if b.tokens >= 1 {
		return false, 0
	}
	return true, l.wait(b)
}

func (l *Limiter) wait(b *bucket) time.Duration {
	perToken := l.rule.Per / time.Duration(l.rule.N)
	return time.Duration((1 - b.tokens) * float64(perToken))
}

// TooMany writes the 429 answer with a Retry-After header.
func TooMany(w http.ResponseWriter, retry time.Duration) {
	secs := int(retry.Seconds() + 0.999)
	w.Header().Set("Retry-After", strconv.Itoa(max(secs, 1)))
	httpx.Error(w, http.StatusTooManyRequests, "rate_limited", "too many requests, try again later")
}

// Middleware limits requests by the key that keyOf returns ("" = not limited).
func Middleware(l *Limiter, keyOf func(*http.Request) string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		if l == nil {
			return next
		}
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if key := keyOf(r); key != "" {
				if ok, retry := l.Allow(key); !ok {
					TooMany(w, retry)
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ByIP limits each client IP (see httpx.ClientIP) on its own.
func ByIP(l *Limiter) func(http.Handler) http.Handler {
	return Middleware(l, httpx.ClientIP)
}
