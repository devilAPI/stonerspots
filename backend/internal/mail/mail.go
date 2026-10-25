// Package mail sends transactional emails via SMTP.
// Features are disabled when config.Mail.Host is empty.
package mail

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/smtp"
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
}

// NewClient creates a mail client.
func NewClient(cfg Config) *Client {
	return &Client{cfg: cfg}
}

// Config returns the client's configuration.
func (c *Client) Config() Config {
	return c.cfg
}

// Send sends an email. Returns an error if mail is not configured.
func (c *Client) Send(ctx context.Context, to, subject, body string) error {
	if !c.cfg.Enabled() {
		return ErrMailDisabled
	}

	addr := fmt.Sprintf("%s:%d", c.cfg.Host, c.cfg.Port)

	// Build message
	msg := "From: " + c.cfg.From + "\r\n" +
		"To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" +
		body + "\r\n"

	// Use TLS if port is 465, otherwise STARTTLS
	if c.cfg.Port == 465 {
		tlsCfg := &tls.Config{ServerName: c.cfg.Host}
		conn, err := tls.Dial("tcp", addr, tlsCfg)
		if err != nil {
			return err
		}
		defer conn.Close()

		client, err := smtp.NewClient(conn, c.cfg.Host)
		if err != nil {
			return err
		}
		defer client.Quit()

		if err := client.Mail(c.cfg.From); err != nil {
			return err
		}
		if err := client.Rcpt(to); err != nil {
			return err
		}
		w, err := client.Data()
		if err != nil {
			return err
		}
		_, err = w.Write([]byte(msg))
		if err != nil {
			return err
		}
		return w.Close()
	}

	// STARTTLS for port 587
	conn, err := smtp.Dial(addr)
	if err != nil {
		return err
	}
	defer conn.Close()

	if err := conn.StartTLS(&tls.Config{ServerName: c.cfg.Host}); err != nil {
		return err
	}

	if err := conn.Mail(c.cfg.From); err != nil {
		return err
	}
	if err := conn.Rcpt(to); err != nil {
		return err
	}
	w, err := conn.Data()
	if err != nil {
		return err
	}
	_, err = w.Write([]byte(msg))
	if err != nil {
		return err
	}
	return w.Close()
}

// ErrMailDisabled is returned when mail is not configured.
var ErrMailDisabled = fmt.Errorf("mail not configured")