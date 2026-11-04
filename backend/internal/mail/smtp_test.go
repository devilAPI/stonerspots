package mail

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"errors"
	"math/big"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

// selfSigned returns a server certificate for 127.0.0.1 and a pool trusting it.
func selfSigned(t *testing.T) (tls.Certificate, *x509.CertPool) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "127.0.0.1"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	leaf, _ := x509.ParseCertificate(der)
	pool := x509.NewCertPool()
	pool.AddCert(leaf)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key, Leaf: leaf}, pool
}

// fakeSMTP is a minimal SMTP server for one test: it records what the
// client did and whether TLS was on when it did it.
type fakeSMTP struct {
	cert     tls.Certificate
	starttls bool // offer STARTTLS
	stall    bool // never greet

	mu        sync.Mutex
	commands  []string
	auth      string // decoded AUTH PLAIN payload
	authInTLS bool
	from, to  string
	data      string
}

func (f *fakeSMTP) record(cmd string) {
	f.mu.Lock()
	f.commands = append(f.commands, cmd)
	f.mu.Unlock()
}

func (f *fakeSMTP) start(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go f.serve(c)
		}
	}()
	return ln.Addr().(*net.TCPAddr).Port
}

func (f *fakeSMTP) serve(c net.Conn) {
	defer c.Close()
	if f.stall {
		time.Sleep(5 * time.Second)
		return
	}
	inTLS := false
	r := bufio.NewReader(c)
	reply := func(s string) { _, _ = c.Write([]byte(s + "\r\n")) }
	reply("220 fake ESMTP")
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return
		}
		line = strings.TrimRight(line, "\r\n")
		verb := strings.ToUpper(strings.SplitN(line, " ", 2)[0])
		f.record(verb)
		switch verb {
		case "EHLO", "HELO":
			reply("250-fake")
			if f.starttls && !inTLS {
				reply("250-STARTTLS")
			}
			reply("250-AUTH LOGIN PLAIN")
			reply("250 8BITMIME")
		case "STARTTLS":
			reply("220 go ahead")
			tc := tls.Server(c, &tls.Config{Certificates: []tls.Certificate{f.cert}})
			if tc.Handshake() != nil {
				return
			}
			c, r, inTLS = tc, bufio.NewReader(tc), true
		case "AUTH":
			parts := strings.Fields(line)
			raw, _ := base64.StdEncoding.DecodeString(parts[len(parts)-1])
			f.mu.Lock()
			f.auth, f.authInTLS = string(raw), inTLS
			f.mu.Unlock()
			reply("235 ok")
		case "MAIL":
			f.mu.Lock()
			f.from = line
			f.mu.Unlock()
			reply("250 ok")
		case "RCPT":
			f.mu.Lock()
			f.to = line
			f.mu.Unlock()
			reply("250 ok")
		case "DATA":
			reply("354 go")
			var b strings.Builder
			for {
				l, err := r.ReadString('\n')
				if err != nil {
					return
				}
				if l == ".\r\n" {
					break
				}
				b.WriteString(l)
			}
			f.mu.Lock()
			f.data = b.String()
			f.mu.Unlock()
			reply("250 queued")
		case "QUIT":
			reply("221 bye")
			return
		default:
			reply("502 no")
		}
	}
}

func testClient(port int, pool *x509.CertPool, user string) *Client {
	c := NewClient(Config{Host: "127.0.0.1", Port: port, Username: user, Password: "s3cret", From: "Stonerspots <noreply@stonerspots.test>"})
	c.tls = &tls.Config{RootCAs: pool}
	return c
}

func TestSendAuthenticatesAfterSTARTTLS(t *testing.T) {
	cert, pool := selfSigned(t)
	f := &fakeSMTP{cert: cert, starttls: true}
	port := f.start(t)
	err := testClient(port, pool, "mailer").Send(context.Background(), "to@stonerspots.test", "Hi", "Body line")
	if err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.auth != "\x00mailer\x00s3cret" || !f.authInTLS {
		t.Fatalf("auth %q, in TLS %v", f.auth, f.authInTLS)
	}
	if f.from != "MAIL FROM:<noreply@stonerspots.test> BODY=8BITMIME" && f.from != "MAIL FROM:<noreply@stonerspots.test>" {
		t.Fatalf("envelope from %q", f.from)
	}
	if f.to != "RCPT TO:<to@stonerspots.test>" {
		t.Fatalf("rcpt %q", f.to)
	}
	if !strings.Contains(f.data, "From: Stonerspots <noreply@stonerspots.test>\r\n") ||
		!strings.Contains(f.data, "Subject: Hi\r\n") || !strings.Contains(f.data, "Body line") {
		t.Fatalf("data %q", f.data)
	}
}

func TestSendWithoutUsernameSkipsAuth(t *testing.T) {
	cert, pool := selfSigned(t)
	f := &fakeSMTP{cert: cert, starttls: true}
	port := f.start(t)
	if err := testClient(port, pool, "").Send(context.Background(), "to@stonerspots.test", "Hi", "x"); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.auth != "" || f.data == "" {
		t.Fatalf("auth %q data %q", f.auth, f.data)
	}
}

// Without STARTTLS neither the password nor the mail (it carries a login
// link) may cross the wire.
func TestSendRefusesPlaintext(t *testing.T) {
	cert, pool := selfSigned(t)
	f := &fakeSMTP{cert: cert, starttls: false}
	port := f.start(t)
	err := testClient(port, pool, "mailer").Send(context.Background(), "to@stonerspots.test", "Hi", "x")
	if !errors.Is(err, ErrNoTLS) {
		t.Fatalf("err = %v", err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, c := range f.commands {
		if c == "AUTH" || c == "MAIL" || c == "DATA" {
			t.Fatalf("sent %s over plaintext: %v", c, f.commands)
		}
	}
}

func TestSendRejectsUntrustedCertificate(t *testing.T) {
	cert, _ := selfSigned(t)
	f := &fakeSMTP{cert: cert, starttls: true}
	port := f.start(t)
	err := testClient(port, x509.NewCertPool(), "mailer").Send(context.Background(), "to@stonerspots.test", "Hi", "x")
	if err == nil {
		t.Fatal("sent over a TLS connection to an untrusted certificate")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.auth != "" {
		t.Fatal("credentials sent")
	}
}

func TestSendHonoursContext(t *testing.T) {
	f := &fakeSMTP{stall: true}
	port := f.start(t)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	start := time.Now()
	err := testClient(port, nil, "").Send(ctx, "to@stonerspots.test", "Hi", "x")
	if err == nil || time.Since(start) > 3*time.Second {
		t.Fatalf("err %v after %v", err, time.Since(start))
	}
}

func TestHasMech(t *testing.T) {
	if !hasMech("LOGIN PLAIN", "PLAIN") || hasMech("LOGIN CRAM-MD5", "PLAIN") || hasMech("", "PLAIN") {
		t.Fatal("hasMech")
	}
}
