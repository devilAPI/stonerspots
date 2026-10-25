# API security plan

The backend is open source and runs on the public internet. Attackers read the code and script against it.

## Done ✓

- bcrypt cost 12, timing-safe login (dummy hash for unknown emails)
- HS256 JWT, 15 min access, rotating refresh tokens (hashed), revoke on password change
- Admin rights from DB every request (immediate revocation)
- SQL placeholders everywhere
- 8 MB uploads, content-checked (JPEG/PNG/WebP/AVIF), 40 MP guard, EXIF stripped
- Path traversal blocked, random 128-bit filenames, `nosniff`
- CORS exact-origin allowlist, no credentials
- systemd: dedicated user, `ProtectSystem=strict`, `NoNewPrivileges`, 0640 config
- HTTP timeouts (2 min), header limit (32 KB), graceful shutdown
- Weak `jwt_secret` rejected on public servers
- Trusted proxy config for X-Forwarded-For
- Security headers: nosniff, frame-ancestors=none, CSP, referrer-policy, CORP, HSTS, no-store
- Rate limits: per-IP 600/min, login 10/min, register 5/hr, refresh 30/min, failed logins 20/hr/account, uploads 30/hr/user
- Request logging with X-Request-Id for 5xx and 429
- Per-user daily quotas: spots 10, updates 50, reviews 20, reports 10
- Unattached photo cleanup (hourly, >24h orphans)
- Global body limit 10 MB

## Next (priority order)

1. **TOTP 2FA for admins** - required for admin actions
2. **HIBP k-anonymity password check** - reject breached passwords on register/change
3. **Email verification on registration** - stops fake accounts / spam
4. **Password reset via email** - secure single-use time-limited tokens
5. **Photo moderation queue** - manual review for NSFW/illegal content
6. **Serve photos only for active/visible spots** - no leaked media from deleted/hidden content
7. **Registration CAPTCHA/proof-of-work** - rate-limiter isn't enough for bot registration
7. **CI security scanning** - `govulncheck`, `gosec`, secret scanning, Dependabot
8. **Admin audit log** - who deleted/locked/changed what
9. **Shorter admin refresh TTL (1h) + "log out everywhere"** - limits blast radius of stolen admin token
10. **JWT key rotation (kid header)** - enables secret rotation without logout
11. **Per-user total upload quota** - disk exhaustion protection
12. **Alerting** - 429 spikes, 5xx bursts, failed login bursts, new admin users
13. **GDPR data export** - user downloads all their data (deletion already works)

## Nice to have (later)

- Device/session management UI (list/revoke)
- Idempotency keys for mutations
- Structured JSON logging + Prometheus metrics
- SBOM + reproducible builds
- Incident runbook
- Data retention policy (auto-delete old tokens/logs)
- Minimize PII in structured logs
