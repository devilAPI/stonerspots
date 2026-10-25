package httpx

import (
	"context"
	"net"
	"net/http"
	"net/netip"
	"strings"
)

type clientIPKey struct{}

// WithClientIP finds the real client address of each request and stores it
// for ClientIP. The connection address is the client unless it is one of
// the trusted reverse proxies; then X-Forwarded-For is read from the right,
// skipping trusted hops, so a client cannot prepend a fake address.
func WithClientIP(trusted []netip.Prefix) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := resolve(r, trusted)
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), clientIPKey{}, ip)))
		})
	}
}

func resolve(r *http.Request, trusted []netip.Prefix) netip.Addr {
	peer := remoteAddr(r)
	if !isTrusted(peer, trusted) {
		return peer
	}
	hops := strings.Split(strings.Join(r.Header.Values("X-Forwarded-For"), ","), ",")
	for i := len(hops) - 1; i >= 0; i-- {
		a, err := netip.ParseAddr(strings.TrimSpace(hops[i]))
		if err != nil {
			break // garbage: stop at the last address we could trust
		}
		a = a.Unmap()
		if !isTrusted(a, trusted) {
			return a
		}
		peer = a
	}
	return peer
}

func remoteAddr(r *http.Request) netip.Addr {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	a, _ := netip.ParseAddr(host)
	return a.Unmap()
}

func isTrusted(a netip.Addr, trusted []netip.Prefix) bool {
	for _, p := range trusted {
		if p.Contains(a) {
			return true
		}
	}
	return false
}

// ClientIP is the rate-limit key of the request's client: its IPv4 address,
// or the /64 network of an IPv6 address (one subscriber usually owns a whole
// /64 and could otherwise rotate through it).
func ClientIP(r *http.Request) string {
	a, ok := r.Context().Value(clientIPKey{}).(netip.Addr)
	if !ok {
		a = remoteAddr(r)
	}
	if !a.IsValid() {
		return "unknown"
	}
	if a.Is6() {
		p, _ := a.Prefix(64)
		return p.String()
	}
	return a.String()
}
