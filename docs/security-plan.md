# API security plan

The backend is open source and runs on the public internet, so assume that
attackers read the code, know every endpoint and script against it. This plan
lists what is already in place, what is missing, and the order to fix it in.

## Already in place (audit, 2026-10-25)

- Passwords: bcrypt cost 12, 10-72 characters; login compares against a dummy
  hash for unknown emails (no timing oracle).
- Tokens: HS256 pinned, expiry required, 15 min access tokens, rotating
  refresh tokens stored hashed; changing the password revokes refresh tokens.
- Admin rights are read from the database on every request, never from the
  token.
- SQL: placeholders everywhere; LIKE patterns are escaped.
- Request bodies are size-limited per handler; uploads are capped at 8 MB,
  checked by content (JPEG/PNG/WebP/AVIF), 40 MP decompression-bomb guard,
  re-encoded without metadata (no EXIF/GPS leak).
- Media: path traversal blocked, `nosniff`, random 128-bit file names.
- Errors: clients get codes, never internal details.
- CORS: exact-origin allow list, no credentials.
- systemd unit: own user, `ProtectSystem=strict`, `NoNewPrivileges`, write
  access only to the data directory. Config file is 0640 root:stonerspots.
- Geocoder proxy: 20 searches/minute per user.

## Phase 1: quick wins

- [ ] HTTP server timeouts and header size limit (slowloris), graceful
      shutdown.
- [ ] Refuse to start with a weak or example `jwt_secret` (anyone who knows
      the secret can sign in as any user, admins included).
- [ ] Stop trusting `X-Forwarded-For` / `X-Real-IP` from everyone; only from
      configured `trusted_proxies`.
- [ ] Security headers on every response (`nosniff`, `frame-ancestors`
      none, no referrer, `Cross-Origin-Resource-Policy`, HSTS on https).
- [ ] Rate limits: per IP on everything, tighter on login, register and
      refresh; per account on failed logins; per user on photo uploads.
- [ ] Log internal errors server-side with a request id (nothing is logged
      today, so attacks and bugs are invisible).

## Phase 2: abuse resistance

- [ ] Per-user quotas for spots, updates, reviews and reports per day.
- [ ] Delete photos that were uploaded but never attached (after 24 h), and
      cap unattached photos per user (disk filling).
- [ ] Do not serve photos of hidden or deleted content.
- [ ] Registration abuse: proof-of-work or CAPTCHA on register, or email
      verification before posting.
- [ ] Global body size limit as a safety net for every route.
- [ ] Audit log of admin actions (who changed / deleted / locked what).

## Phase 3: accounts and admins

- [ ] TOTP two-factor authentication, required for admins.
- [ ] Reject passwords from known breaches (HIBP k-anonymity range API).
- [ ] Shorter refresh lifetime for admins; "log out everywhere".
- [ ] JWT key rotation (key id in the token header).

## Phase 4: process

- [ ] `SECURITY.md`: how to report vulnerabilities privately.
- [ ] CI: `govulncheck`, `gosec`, Dependabot for Go and Flutter, secret
      scanning.
- [ ] Deployment guide: TLS-terminating reverse proxy (Caddy), API bound to
      localhost, MariaDB user with only the needed privileges and bound to
      localhost, backups.
