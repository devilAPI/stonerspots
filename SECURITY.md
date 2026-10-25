# Security Policy

## Supported Versions

We release security patches for the latest version of the `main` branch. Older versions are not supported.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, send an email to **security@stonerspots.example** (replace with actual contact) with:

- A description of the vulnerability
- Steps to reproduce
- Impact assessment
- Any suggested fixes

We will acknowledge receipt within 48 hours and provide a timeline for a fix. We aim to patch critical vulnerabilities within 7 days.

## Security Architecture

This API is designed for public internet deployment. Key security measures:

### Authentication & Authorization
- Passwords: bcrypt cost 12, 10-72 character enforcement
- Login timing-safe (dummy hash for unknown emails)
- Access tokens: HS256, 15 min TTL, algorithm pinned
- Refresh tokens: rotating, stored hashed, revoked on password change
- Admin rights read from DB on every request (immediate revocation)

### Rate Limiting
- Per-IP: 600 req/min (all endpoints)
- Login: 10 req/min per IP
- Register: 5 req/hour per IP
- Refresh: 30 req/min per IP
- Failed logins: 20/hour per account (stops credential stuffing across IPs)
- Photo uploads: 30/hour per user

### Transport & Headers
- CORS: exact-origin allowlist, no credentials
- Security headers on every response:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`
  - `Referrer-Policy: no-referrer`
  - `Cross-Origin-Resource-Policy: cross-origin`
  - `Cache-Control: no-store`
  - `Strict-Transport-Security: max-age=31536000` (when HTTPS)
- Trusted proxy configuration required for correct client IP

### Data Protection
- Upload validation: content-type sniffing, 8 MB limit, 40 MP decompression bomb guard
- Images re-encoded without EXIF/GPS metadata
- Random 128-bit file names, path traversal blocked
- No personal data in shared caches (`Cache-Control: no-store`)

### Infrastructure (Production)
- systemd: dedicated user, `ProtectSystem=strict`, `NoNewPrivileges`, minimal write access
- Config file permissions: `0640 root:app`
- Database: least-privilege user, localhost-only binding
- Reverse proxy (Caddy) handles TLS termination

## Dependencies

- Go standard library + well-maintained third-party packages
- Regular `govulncheck` and `gosec` scans in CI
- Dependabot alerts for Go and Flutter dependencies

## Cryptography

- TLS 1.2+ enforced by reverse proxy
- JWT: HS256 with 32+ byte secret (config-validated)
- Password hashing: bcrypt cost 12
- Tokens: crypto/rand (32 bytes for refresh, 16 bytes for upload keys)