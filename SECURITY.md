# Security

## Supported Versions

We release security patches for the latest version of the `main` branch. Older versions are not supported.
Version 2.0 is being finished on the `v2` branch; the security work listed under
"In progress" below lands there first.

## Reporting a Vulnerability

Please report vulnerabilities privately through GitHub: the repository's
**Security** tab → **Report a vulnerability**. Do not put details of an open
vulnerability in a public issue; if private reporting is not available, open
an issue that only asks for a contact.

Please include:
- A description of the vulnerability
- Steps to reproduce
- Impact assessment
- Any suggested fixes

## Security Architecture

This API is designed for public internet deployment behind a reverse proxy.
This section describes what the code does today; known gaps are listed under
[In progress](#in-progress-on-v2) and in [docs/security-plan.md](docs/security-plan.md).

### Authentication & Authorization
- Passwords: bcrypt cost 12, 10-72 character enforcement, checked against
  Have I Been Pwned (k-anonymity) on register and password change
- Login timing-safe (dummy hash for unknown emails)
- Access tokens: HS256, 15 min TTL, algorithm pinned
- Refresh tokens: rotating, stored hashed, reuse revokes the whole family,
  revoked on password change and ban
- Admin rights read from DB on every request (immediate revocation)
- Admin TOTP 2FA exists but is optional and not yet usable from the web app
  (in progress)

### Rate Limiting
- Per-IP: 600 req/min (all endpoints)
- Login: 10 req/min per IP
- Register: 5 req/hour per IP, plus a proof-of-work challenge (difficulty
  being raised, in progress)
- Refresh: 30 req/min per IP
- Failed logins: 20/hour per account (stops credential stuffing across IPs)
- Photo uploads: 30/hour per user
- Daily per-user quotas for spots, updates, reviews, reports and comments
  (kept in memory: they restart with the API)

Per-IP limits need the real client address: behind a reverse proxy,
`trusted_proxies` must name it (new installs listen on `127.0.0.1:8080` and
trust the loopback proxy; the API warns at start when this looks wrong).

### Transport & Headers
- TLS is terminated by the reverse proxy (Caddy example in the README); the
  installer does not set one up
- CORS: exact-origin allowlist, no credentials
- Security headers on every response:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`
  - `Referrer-Policy: no-referrer`
  - `Cross-Origin-Resource-Policy: cross-origin`
  - `Cache-Control: no-store` (photos are served cacheable)
  - `Strict-Transport-Security: max-age=31536000` (when `public_base_url` is HTTPS)
- X-Forwarded-For is only read from configured `trusted_proxies`

### Data Protection
- Uploads: 8 MB limit, decoded and re-encoded (JPEG/PNG/WebP/AVIF), 40 MP
  limit; hardening of the image decoding is in progress (see below)
- Images re-encoded without EXIF/GPS metadata
- Random 128-bit file names, path traversal blocked
- No personal data in shared caches (`Cache-Control: no-store`)
- Users can download everything stored about them (`GET /me/export`) and
  delete their account with all of it

### Infrastructure (Production)
- systemd unit written by `install-backend.sh`: dedicated user, no
  capabilities, `NoNewPrivileges`, `ProtectSystem=strict` with write access
  only to its own state directory and the update request folder,
  `PrivateTmp`/`PrivateDevices`/`ProtectHome`, kernel and clock protections,
  `RestrictNamespaces`, `SystemCallFilter=@system-service`, only
  IPv4/IPv6/Unix sockets, `UMask=0077`, `MemoryMax=1536M` with `GOMEMLIMIT`,
  task and file limits
- The root update unit (admin-page updates) is sandboxed to the folders an
  update writes, with a start timeout; it reads the API's update request
  with the API user's rights and acts only on the exact words `release`/`dev`
- Root never touches files inside folders the service user can write to
- Config file permissions: `0640 root:stonerspots`
- Database: own user, localhost only (see the README checklist). Not least
  privilege yet: the API applies migrations at start, so its user can change
  the tables of its database
- Home server checklist (firewall, backups, fail2ban, updates, monitoring):
  [README](README.md#home-server-checklist)

### Release integrity
- CI signs `SHA256SUMS.txt` of the backend tarballs with an ed25519 key
  (`ssh-keygen -Y sign`, secret `RELEASE_SIGNING_KEY`); with the public key
  in `/etc/stonerspots/release-signing.pub` the installer refuses unsigned
  or wrongly signed builds before unpacking or running anything from them
- Backend tarballs come only from the backend build jobs, with GitHub build
  provenance (`gh attestation verify`)
- GitHub Actions pinned to commit SHAs; every job has only the permissions
  it needs

## Dependencies

- Go standard library + well-maintained third-party packages
- `govulncheck` and `go vet` in CI (workflow "Security checks": pushes and
  pull requests to `main` and `v2`, and weekly); `gosec` is run by hand, not in CI
- Dependabot version updates for Go modules, Flutter packages and GitHub
  Actions (`.github/dependabot.yml`); Dependabot alerts and security updates
  must be switched on in the repository settings

## Cryptography

- TLS 1.2+ enforced by reverse proxy
- JWT: HS256 with 32+ byte secret (config-validated)
- Password hashing: bcrypt cost 12
- Tokens: crypto/rand (32 bytes for refresh, 16 bytes for upload keys)

## In progress on v2

Found in a security review and being fixed on the `v2` branch:

- Image decoding: outdated `golang.org/x/image` with known decoder bugs, and
  memory use of large images (one account could exhaust a small server's memory)
- Admin 2FA: make it required for admins, usable from the web app, limited
  in attempts, and checked by every admin action
- Email verification and password reset: mail sending does not work yet;
  reset/verification tokens are stored in plain text and not rate limited
- Reported content is hidden automatically after 3 reports, which a few fake
  accounts can abuse
- Proof-of-work for registration is too easy to be a real obstacle
- Login failure counters can be flushed by flooding the limiter

Known and not started yet (see [docs/security-plan.md](docs/security-plan.md)):
photos of hidden or deleted content stay reachable by URL (and cached),
banned users' content stays visible, no limits on follows/likes, quotas reset
on restart, web tokens live in `localStorage` of the shared
`devilapi.github.io` origin, no separate database user for migrations.
