# Handoff: continuing Stonerspots on another machine

Paste the block below into a new Claude Code session in a fresh clone of
this repo. Everything in it is already public in this repo; credentials,
server addresses and private data are deliberately left out (see "Not in
the repo").

---

```text
You are continuing work on Stonerspots (github.com/devilAPI/stonerspots), a
community map of outdoor spots with a photo feed, profiles and a layer of
German § 5 KCanG no-consumption zones from OpenStreetMap. Read README.md,
CHANGELOG.md and docs/HANDOFF.md first.

Stack: Flutter app in app/ (Android, iOS, web, Linux; Riverpod, flutter_map),
Go API in backend/ (chi, MariaDB 11.4, migrations in backend/migrations).
No PHP, no Postgres.

State (2026-11-14):
- Work happens on branch v2. main is fast-forwarded to v2 only when
  releasing. Latest release: v1.0.13. v2 is at 1.0.14 (pubspec +
  CHANGELOG), not released yet: zones are now drawn once into an image
  that moves with the map (ZoneRaster in app/lib/features/zones/
  zone_paint.dart) instead of re-stroking every zone every frame.
- Recent features: user search in the map search (GET /users/search,
  backend/internal/textmatch for ranking), profile bio (PUT /me/bio,
  migration 0029), smarter spot search, zone-status fix (Future.wait drops
  SynchronousFuture results; zonesNear awaits tiles one by one), mobile-web
  keyboard fix (shell Scaffolds resizeToAvoidBottomInset: false).

Working rules:
- Commit and push v2 after each finished feature (tests + analyze green).
  Never commit secrets: app/env/local.json, *.jks and the release signing
  keys are git-ignored and must stay so.
- Release order: bump app/pubspec.yaml version + new CHANGELOG section,
  commit, push v2; then the tag vX.Y.Z is pushed on that commit (the user
  does this, or asks explicitly for that release); only after the release
  run has started, `git push origin v2:main`. Tag before main, because
  GitHub Pages keeps the first deployment of a commit. CI checks that the
  tag equals the pubspec version.
- Right after a release, the next change bumps the version again
  (X.Y.Z+1) with a new CHANGELOG section.
- Never deploy to the production server; it runs main's release builds.
- Zones are Germany-only (shared OSM border, backend/cmd/germanyborder).
- The app is not legal advice; legal texts say so.

Local dev:
- DB: `docker compose up -d --wait` (MariaDB on 127.0.0.1:3307, dev-only
  password in docker-compose.yml). Backend tests: `make test` (uses
  TEST_DATABASE_URL from the Makefile).
- After a schema change: `UPDATE_SCHEMA=1 go test ./internal/server -run
  TestSchemaFile` in backend/ regenerates schema.example.sql.
- API: see README "Run it locally".
- App: copy app/env/local.example.json to app/env/local.json and fill in
  the map keys. Fastest build: `cd app && flutter build linux --debug
  --dart-define-from-file=env/local.json`, run
  build/linux/x64/debug/bundle/app. Tests: `flutter test`, `flutter
  analyze`. Kill the app with `pkill -x app` (never `pkill -f` with a
  pattern that is in your own shell command).
- Judge performance only in profile builds. Web perf: `flutter build web
  --profile`, serve build/web, drive headless Chromium over CDP with GPU
  flags (`--enable-gpu --use-angle=gl`; the default is software rendering).
- Web pitfalls: bitwise ops are 32-bit unsigned on the web; CI runs
  test/zones/germany_test.dart in Chrome.
- When CI's govulncheck fails on a Go stdlib vuln, bump the go line in
  backend/go.mod.

Open items:
- 1.0.14 is waiting to be released (see release order).
- iOS home-screen PWA: Flutter issues #115829 / #111896 (dead taps at the
  bottom of the screen) are upstream.
```

---

## Not in the repo

These live only on the main PC and the server and have to be copied over
by hand if the other machine needs them:

- `app/env/local.json` (map API keys)
- Android keystore (`*.jks`) and the release signing key pair
- SSH key and notes for the home server, and the deploy scripts/configs
- Private spot data (GPX files)
