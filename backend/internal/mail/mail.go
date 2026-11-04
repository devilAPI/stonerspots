// Package mail sends transactional emails via SMTP.
// Features are disabled when config.Mail.Host is empty.
package mail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/mail"
	"net/smtp"
	"slices"
	"strconv"
	"strings"
	"time"
)

// Config holds SMTP settings.
type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

// Enabled reports whether mail is configured.
func (c Config) Enabled() bool {
	return c.Host != "" && c.From != ""
}

// Client sends emails.
type Client struct {
	cfg Config
	// tls is the TLS configuration for STARTTLS and port 465 (tests trust
	// their own certificate through it).
	tls *tls.Config
}

// NewClient creates a mail client.
func NewClient(cfg Config) *Client {
	return &Client{cfg: cfg}
}

// Enabled reports whether mail is configured (false for a nil Client).
func (c *Client) Enabled() bool { return c != nil && c.cfg.Enabled() }

// Config returns the client's configuration.
func (c *Client) Config() Config {
	return c.cfg
}

// Errors returned by Send.
var (
	// ErrMailDisabled is returned when mail is not configured.
	ErrMailDisabled = errors.New("mail not configured")
	// ErrNoTLS: the server offers no STARTTLS. Nothing is sent: neither the
	// password nor the mail (it carries a login link) goes out in plain text.
	ErrNoTLS = errors.New("mail: SMTP server does not offer STARTTLS")
	// ErrNoAuth: a username is configured but the server offers no AUTH PLAIN.
	ErrNoAuth = errors.New("mail: SMTP server does not offer AUTH PLAIN")
)

// defaultTimeout bounds the SMTP dialogue when ctx has no deadline.
const defaultTimeout = 30 * time.Second

func (c *Client) tlsConfig() *tls.Config {
	if c.tls != nil {
		t := c.tls.Clone()
		t.ServerName = c.cfg.Host
		return t
	}
	return &tls.Config{ServerName: c.cfg.Host, MinVersion: tls.VersionTLS12}
}

// Send sends an email: over implicit TLS on port 465, otherwise with
// STARTTLS (required), then AUTH PLAIN with the configured username and
// password when one is set. ctx bounds the whole dialogue.
func (c *Client) Send(ctx context.Context, to, subject, body string) error {
	if !c.cfg.Enabled() {
		return ErrMailDisabled
	}
	// The envelope needs the bare address; From may be "Name <addr>".
	from, err := mail.ParseAddress(c.cfg.From)
	if err != nil {
		return fmt.Errorf("mail: from address: %w", err)
	}
	if _, ok := ctx.Deadline(); !ok {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, defaultTimeout)
		defer cancel()
	}
	deadline, _ := ctx.Deadline()

	addr := net.JoinHostPort(c.cfg.Host, strconv.Itoa(c.cfg.Port))
	var d net.Dialer
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	_ = conn.SetDeadline(deadline)
	// stop a stuck dialogue as soon as ctx ends, not only at the deadline
	stop := context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Unix(1, 0)) })
	defer stop()

	implicitTLS := c.cfg.Port == 465
	if implicitTLS {
		tc := tls.Client(conn, c.tlsConfig())
		if err := tc.HandshakeContext(ctx); err != nil {
			return err
		}
		conn = tc
	}
	client, err := smtp.NewClient(conn, c.cfg.Host)
	if err != nil {
		return err
	}
	defer client.Close()
	if err := client.Hello("localhost"); err != nil {
		return err
	}
	if !implicitTLS {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return ErrNoTLS
		}
		if err := client.StartTLS(c.tlsConfig()); err != nil {
			return err
		}
	}
	if c.cfg.Username != "" {
		if ok, mechs := client.Extension("AUTH"); !ok || !hasMech(mechs, "PLAIN") {
			return ErrNoAuth
		}
		// The connection is TLS by now, which smtp.PlainAuth checks again.
		if err := client.Auth(smtp.PlainAuth("", c.cfg.Username, c.cfg.Password, c.cfg.Host)); err != nil {
			return fmt.Errorf("mail: authentication failed: %w", err)
		}
	}
	if err := client.Mail(from.Address); err != nil {
		return err
	}
	if err := client.Rcpt(to); err != nil {
		return err
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write([]byte(message(c.cfg.From, to, subject, body))); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return client.Quit()
}

func message(from, to, subject, body string) string {
	return "From: " + from + "\r\n" +
		"To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" +
		body + "\r\n"
}

func hasMech(list, want string) bool {
	return slices.Contains(strings.Fields(list), want)
}
