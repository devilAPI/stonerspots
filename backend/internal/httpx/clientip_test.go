package httpx

import (
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"
)

func TestClientIP(t *testing.T) {
	proxy := []netip.Prefix{netip.MustParsePrefix("127.0.0.1/32"), netip.MustParsePrefix("10.0.0.0/8")}
	for name, tc := range map[string]struct {
		remote  string
		xff     []string
		trusted []netip.Prefix
		want    string
	}{
		"direct":                             {"203.0.113.7:5000", nil, nil, "203.0.113.7"},
		"spoofed header, no proxies trusted": {"203.0.113.7:5000", []string{"1.2.3.4"}, nil, "203.0.113.7"},
		"spoofed header from untrusted peer": {"203.0.113.7:5000", []string{"1.2.3.4"}, proxy, "203.0.113.7"},
		"behind proxy":                       {"127.0.0.1:9", []string{"198.51.100.2"}, proxy, "198.51.100.2"},
		"client prepends a fake hop":         {"127.0.0.1:9", []string{"1.2.3.4, 198.51.100.2"}, proxy, "198.51.100.2"},
		"two trusted hops":                   {"127.0.0.1:9", []string{"198.51.100.2, 10.1.1.1"}, proxy, "198.51.100.2"},
		"several header lines":               {"127.0.0.1:9", []string{"1.2.3.4", "198.51.100.2"}, proxy, "198.51.100.2"},
		"garbage stops at last trusted":      {"127.0.0.1:9", []string{"evil"}, proxy, "127.0.0.1"},
		"proxy without header":               {"127.0.0.1:9", nil, proxy, "127.0.0.1"},
		"ipv6 grouped per /64":               {"[2001:db8:1:2:aaaa::1]:443", nil, nil, "2001:db8:1:2::/64"},
		"ipv4-mapped ipv6":                   {"[::ffff:203.0.113.7]:1", nil, nil, "203.0.113.7"},
	} {
		t.Run(name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "/", nil)
			r.RemoteAddr = tc.remote
			for _, v := range tc.xff {
				r.Header.Add("X-Forwarded-For", v)
			}
			var got string
			WithClientIP(tc.trusted)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
				got = ClientIP(r)
			})).ServeHTTP(httptest.NewRecorder(), r)
			if got != tc.want {
				t.Fatalf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestClientIPWithoutMiddleware(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "192.0.2.9:1"
	r.Header.Set("X-Forwarded-For", "1.1.1.1")
	if got := ClientIP(r); got != "192.0.2.9" {
		t.Fatal(got)
	}
}
