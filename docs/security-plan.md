# API security plan

The backend is open source and runs on the public internet. Attackers read the code and script against it.

Status as of the security review of `v2` (November 2026). "Done" means
checked in the code, not just planned.

## Done ✓

- bcrypt cost 12, timing-safe login (dummy hash for unknown emails)
- HS256 JWT, 15 min access, rotating refresh tokens (hashed, family revoked on reuse), revoke on password change and ban
- Admin rights from DB every request (immediate revocation)
- SQL placeholders everywhere (no string-built query with user input found)
- HIBP k-anonymity password check on register and password change
- 8 MB uploads, re-encoded, EXIF stripped
- Path traversal blocked, random 128-bit filenames, `nosniff`
- CORS exact-origin allowlist, no credentials
- HTTP timeouts (2 min), header limit (32 KB), graceful shutdown
- Weak `jwt_secret` rejected on public servers
- Trusted proxy config for X-Forwarded-For; new configs listen on 127.0.0.1 and trust the loopback proxy, startup warning when listen address and `trusted_proxies` do not fit
- Security headers: nosniff, frame-ancestors=none, CSP, referrer-policy, CORP, HSTS, no-store
- Rate limits: per-IP 600/min, login 10/min, register 5/hr, refresh 30/min, failed logins 20/hr/account, uploads 30/hr/user
- Request logging with X-Request-Id for 5xx and 429
- Per-user daily quotas: spots 10, updates 50, reviews 20, reports 10, comments 100 (in memory, reset on restart)
- Unattached photo cleanup (hourly, >24h orphans)
- Global body limit 10 MB
- systemd sandbox: dedicated user, no capabilities, `ProtectSystem=strict`, `NoNewPrivileges`, syscall and socket filters, `MemoryMax=1G` + `GOMEMLIMIT`, `UMask=0077`, data folder as `StateDirectory`; 0640 config
- Installer as root never follows paths the service user controls; admin-page update requests read with the service user's rights, exact words only, bounded in size and time; root update unit sandboxed with a timeout
- Signed backend releases (`SHA256SUMS.txt.sig`, enforced once the server has the public key), backend tarballs only from the backend jobs, build provenance
- CI: actions pinned to commit SHAs, least-privilege job permissions, `govulncheck` + `go vet` (push/PR to main and v2, weekly), Dependabot for Go, pub and Actions
- Home server guide: Caddy, firewall, DB on localhost, backups, fail2ban, OS updates, monitoring (README)
- GDPR data export: `GET /me/export` (JSON download of everything stored about the caller, without password hash, 2FA secret or token hashes; 3 a day per user), "Download my data" in the app
- Operator details for the legal notice only from the server config (`legal:`, `GET /legal`), never in the repository
- HIBP check sends the 5-character SHA-1 prefix the range API expects (it sent 10 before, which the API refused)

## In progress on v2

Found in the review; fixes are being made on the `v2` branch right now:

1. **Image decoding** - update `golang.org/x/image` (12 known reachable decoder bugs), let only JPEG/PNG/WebP/AVIF decoders see uploads, cap concurrent decodes and pixels (memory)
2. **TOTP 2FA for admins** - exists but optional; make it required, usable from the web app (`X-TOTP` / step-up token), attempt-limited, replay-safe, and enforced on every admin power (comment delete, tag edits, locked spots)
3. **Email verification and password reset** - code exists but mail does not work (no SMTP auth, placeholder links, cancelled context); tokens to be stored hashed and indexed, forgot-password rate limited, token checked before HIBP
4. **Report auto-hide** - 3 reports hide content immediately; sock-puppet accounts can censor anything
5. **Registration proof-of-work** - exists, difficulty too low to slow scripts; separate key from the JWT secret
6. **Login failure limiter** - attacker-chosen keys can flush the per-account counter

## Next (priority order)

1. **Serve photos only for active/visible content** - photos of hidden/deleted updates and banned users are still served (and cached for a year)
2. **Signed releases in practice** - owner creates the key, sets `RELEASE_SIGNING_KEY`, puts the public key on the server (README "Signed releases")
3. **Separate migration DB user** - the API runs migrations at start, so its DB user needs DDL; split into a migrate step with its own user and a DML-only runtime user without `multiStatements`
4. **Banned users' content** - decide whether a ban hides their spots/updates/comments; check bans in the auth middleware for writes
5. **Limits on follows / likes / list writes**, quotas that survive restarts
6. **Per-endpoint limits for search and feed** (the most expensive unauthenticated queries)
7. **Log failed logins / TOTP failures / refresh reuse** as one line each (fail2ban, alerting)
8. **CI: `gosec`** (with the known false positives excluded), secret scanning
9. **Admin audit log** - who deleted/locked/changed what
10. **Shorter admin refresh TTL (1h) + "log out everywhere"** - limits blast radius of stolen admin token
11. **JWT key rotation (kid header)** - enables secret rotation without logout
12. **Per-user total upload quota** - disk exhaustion protection
13. **Alerting** - 429 spikes, 5xx bursts, failed login bursts, new admin users, admin-page updates
14. **Web app on its own origin** - tokens in `localStorage` are shared with every `devilapi.github.io` page; add a CSP
15. **Photo moderation** - photos are approved on upload; the admin photo list can review and delete them afterwards, no pre-moderation queue

## Nice to have (later)

- Device/session management UI (list/revoke)
- Idempotency keys for mutations
- Structured JSON logging + Prometheus metrics
- SBOM + reproducible builds
- Incident runbook
- Data retention policy (auto-delete expired refresh tokens, old activity rows, logs)
- Minimize PII in structured logs
