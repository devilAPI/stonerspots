# Stonerspots

A community map for finding good places to smoke weed outdoors: nice benches,
rivers, lakes, viewpoints. People add spots, post photo updates, and browse a
small picture feed. Spots can be anywhere in the world; address search and
coordinates are not limited to a region.

- **App:** Flutter (Android, iOS, web, Linux, Windows, macOS) in [`app/`](app);
  the Android and desktop apps [update themselves](#app-updates)
- **API:** Go + chi + MariaDB (spatial index for "spots in view") in [`backend/`](backend)
- **Plan / decisions:** [`docs/superpowers/plans/`](docs/superpowers/plans)
- **Ideas / to do:** [`docs/ideas.md`](docs/ideas.md)

> Spots are community content. Consumption near schools, playgrounds and in
> pedestrian zones is restricted by law (KCanG in Germany). The map shows these
> zones from OpenStreetMap data (see [Verbotszonen](#verbotszonen)); they can be
> incomplete and are no legal advice. Users must confirm they are 18+.

## Stonerspots 1.0

The first release. What's in it is in [`CHANGELOG.md`](CHANGELOG.md), in
short:

- **Map** with spot search (Ctrl+K) and a compass.
- **Spots** with photos, weather (Open-Meteo, no key), reviews, comments and
  updates.
- **Feed**, also as "Following": only updates of people you follow.
- **Profiles** with pictures, following and followers; **activity** (a bell
  on the profile tab: who followed you, commented, liked or rated your spot).
- **Saved lists**, **admin tools** (reports, users, spots, tags, backend
  updates, two-factor codes) and **automatic, signed updates** for the
  Android and desktop apps and the backend.

How a release is made: [Releasing 1.0](#releasing-10).

Config key added late in development: `limits.comments_per_day` (comments on spots per user per
day, default 100; see `backend/config.example.yaml`). An existing
`config.yaml` without it keeps working with the default.

## Run it locally

```sh
# 1. database (MariaDB 11.4 on 127.0.0.1:3307)
make db-up

# 2. API on 127.0.0.1:8080 (config.yaml: database, JWT secret, CORS, ...; env vars
#    override it; ADDR=:8080 lets a phone in the LAN connect)
cd backend
cp config.example.yaml config.yaml
go run ./cmd/api

# 3. app (Linux desktop compiles fastest; use -d chrome / an emulator otherwise)
cd app
cp env/local.example.json env/local.json   # then fill in CARTO_KEY (optional)
flutter run -d linux --dart-define-from-file=env/local.json
```

The table layout is in `backend/schema.example.sql` (generated from
`backend/migrations/`, which the API applies on start).

Tests: `make test` (backend, needs the database) and `cd app && flutter test`.

Optional demo data from a GPX file: `cd backend && go run ./cmd/seedgpx -gpx spots.gpx`.

## Install the backend on a server

`install-backend.sh` downloads the newest backend build from the GitHub
releases (amd64 or arm64), verifies its checksum (and its signature, once
the server has the [release key](#signed-releases)) and installs it as the
systemd service `stonerspots-backend`. Run it again to update.

One-liner, straight from GitHub:

```sh
# newest release (vX.Y.Z)
curl -fsSL https://raw.githubusercontent.com/devilAPI/stonerspots/main/install-backend.sh | sudo bash
# newest dev build
curl -fsSL https://raw.githubusercontent.com/devilAPI/stonerspots/main/install-backend.sh | sudo bash -s -- --dev
```

Or from a checkout: `sudo ./install-backend.sh [--dev | --release] [--force]`.

Running it again updates an existing install: it stays on its channel (a dev
install keeps taking dev builds, `--release` switches it), does nothing when
already up to date (`--force` reinstalls), never touches `config.yaml` (it only
lists settings that are new in `config.example.yaml`) and restarts the service
only if it was meant to run. The previous binary stays as
`/opt/stonerspots/api.previous`; if the service does not stay up after an update,
the script goes back to it and reports the update as failed.

Releases are the regular GitHub releases `vX.Y.Z` (GitHub's "latest"), with
`stonerspots-backend-vX.Y.Z-linux-<arch>.tar.gz` and a signed `SHA256SUMS.txt`;
dev builds the prereleases `dev-<n>` with `stonerspots-backend-dev-<n>-…`. The
script takes only a tarball named after the tag it is published under. It
refuses to switch to a build whose database migrations are older than the
installed ones (say from a dev build to a release made before it), since the
database can't go back; nothing is changed then.

Binaries go to `/opt/stonerspots`, photos to `/var/lib/stonerspots/uploads`.
The first run creates `/etc/stonerspots/config.yaml` with a random JWT secret;
fill in the database there (MariaDB 11.4, not installed by the script), then
`sudo systemctl start stonerspots-backend`. The API listens on
`127.0.0.1:8080` only: put a reverse proxy with HTTPS in front of it
(see [Reverse proxy](#reverse-proxy-caddy) and the
[home server checklist](#home-server-checklist)).

The systemd units are rewritten by every run of the script (they are
sandboxed: no capabilities, read-only system, `MemoryMax=1G`, syscall
filter, ...). Put local changes into a drop-in, which stays:
`sudo systemctl edit stonerspots-backend`.

Admins can also update the backend from the app: admin page → Actions →
"Update backend to newest" / "… newest dev". The API runs unprivileged, so
it only drops the wanted channel into `/var/lib/stonerspots-update/request/`;
the root unit `stonerspots-update.path` picks that up and runs the installed
copy of this script (`/opt/stonerspots/install-backend.sh --release|--dev`),
reporting progress and its log back to the page. It hands over to the script
inside the new build, so installer fixes apply to the update that delivers them.
Installs from before this feature get the units by running `install-backend.sh`
once more. Prefer "newest" (releases) on a real server: the dev channel is a
new build for every push to main.

### Signed releases

The installer runs as root and runs what it downloads, so it should only
accept builds made by this repository's CI. CI signs `SHA256SUMS.txt` (the
checksums of the backend tarballs) with an ed25519 key; a server that has the
public key refuses any build without a valid signature, including the
installer inside the archive. Without the key the installer only checks the
checksums and prints a warning.

1. Make the key pair on your own computer (not on the server, not in the repo).
   CI cannot type a passphrase, hence `-N ''`; keep the private key in your
   password manager and delete the file afterwards:

   ```sh
   ssh-keygen -t ed25519 -N '' -C stonerspots-release -f stonerspots-release
   ```

2. Add the private key as the repository secret `RELEASE_SIGNING_KEY`
   (Settings → Secrets and variables → Actions → New repository secret,
   paste the whole file including the `BEGIN`/`END` lines), or
   `gh secret set RELEASE_SIGNING_KEY < stonerspots-release`.
3. Push to main and wait until the new `dev-<n>` release has a
   `SHA256SUMS.txt.sig` (the "Sign backend checksums" job warns when the
   secret is missing; for a release `vX.Y.Z` it fails instead).
4. Only then put the public key on the server (from then on, unsigned builds
   are refused):

   ```sh
   sudo mkdir -p /etc/stonerspots
   sudo install -m 0644 -o root -g root stonerspots-release.pub /etc/stonerspots/release-signing.pub
   ```

   For a new server do this before the first `install-backend.sh` run. The
   script you pipe from GitHub is not covered by the signature (the builds
   it installs are): read it first, or run it from a checkout you trust.

Check a download by hand:

```sh
printf 'stonerspots-release %s\n' "$(cat stonerspots-release.pub)" > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I stonerspots-release -n stonerspots-release \
  -s SHA256SUMS.txt.sig < SHA256SUMS.txt
sha256sum -c --ignore-missing SHA256SUMS.txt
# GitHub build provenance of the tarball (needs the gh CLI)
gh attestation verify stonerspots-backend-dev-42-linux-amd64.tar.gz --repo devilAPI/stonerspots
```

What it protects against: a malicious step in any other CI job (Flutter,
pub packages, third-party actions) or a file swapped in a release. What it
does not: anyone who can push workflow changes to main can get builds
signed, so protect main (branch protection, 2FA on the GitHub account). If
the key leaks, make a new pair, replace the secret and the file on the server.

### Reverse proxy (Caddy)

The API speaks plain HTTP on `127.0.0.1:8080`; Caddy in front of it gets the
TLS certificate (Let's Encrypt), limits request bodies and passes the real
client address on. `/etc/caddy/Caddyfile` (replace `api.example.org`; its DNS
name must point at your public IP, a DynDNS name works):

```caddyfile
{
	servers {
		timeouts {
			read_header 10s
			read_body 2m
			write 2m
			idle 2m
		}
	}
}

api.example.org {
	encode zstd gzip
	request_body {
		max_size 10MB
	}
	reverse_proxy 127.0.0.1:8080 {
		# the client as Caddy sees it; anything the client sent is replaced
		header_up X-Forwarded-For {remote_host}
		transport http {
			dial_timeout 5s
			response_header_timeout 2m
		}
	}
	log {
		output file /var/log/caddy/stonerspots.log {
			roll_size 50MiB
			roll_keep 5
		}
		format json
	}
}
```

And in `/etc/stonerspots/config.yaml` (new installs have these already):

```yaml
addr: "127.0.0.1:8080"
public_base_url: "https://api.example.org"
trusted_proxies: ["127.0.0.1/32", "::1/128"]
```

Without `trusted_proxies` every request seems to come from Caddy, so all
clients share one rate limit and one script can lock everybody out of logging
in; the API warns about that at start. `sudo systemctl reload caddy` and
`sudo systemctl restart stonerspots-backend` after changing them.

### Home server checklist

- **Only Caddy is reachable.** `addr: "127.0.0.1:8080"` and
  `trusted_proxies` as above. On the router forward only TCP 80 and 443 to
  the server, never 8080 or 3306. Firewall on the server, e.g. with ufw:

  ```sh
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp   # SSH from the LAN only
  sudo ufw allow 80,443/tcp
  sudo ufw enable
  ```

  or nftables (`/etc/nftables.conf`, then `sudo systemctl enable --now nftables`):

  ```
  table inet filter {
    chain input {
      type filter hook input priority 0; policy drop;
      ct state established,related accept
      iif lo accept
      meta l4proto { icmp, ipv6-icmp } accept
      ip saddr 192.168.1.0/24 tcp dport 22 accept
      tcp dport { 80, 443 } accept
    }
  }
  ```

  Ports published by Docker bypass ufw: a MariaDB container must publish
  `127.0.0.1:3306:3306`, not `3306:3306`.
- **Database on localhost only.** MariaDB with `bind-address = 127.0.0.1`
  (Debian: `/etc/mysql/mariadb.conf.d/50-server.cnf`), its own user with a
  long random password instead of the example `stonerspots`:

  ```sql
  CREATE DATABASE stonerspots CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  CREATE USER 'stonerspots'@'127.0.0.1' IDENTIFIED BY '<openssl rand -hex 24>';
  GRANT ALL PRIVILEGES ON stonerspots.* TO 'stonerspots'@'127.0.0.1';
  ```

  Limitation: the API applies its migrations on every start, so this user
  needs to change tables (all rights on its own database). It gets no rights
  on other databases and none of the global ones (`FILE`, `SUPER`, ...). A
  separate migration user is not supported yet. Set `database.port: 3306` in
  `config.yaml` (the example uses the dev port 3307).
- **Backups of the database and the photos**, encrypted and off the machine,
  e.g. with [restic](https://restic.net) (encrypts by default) from a root
  cron job or systemd timer:

  ```sh
  #!/bin/sh
  # /usr/local/sbin/stonerspots-backup (root, 0700)
  set -eu
  export RESTIC_REPOSITORY=sftp:backup@nas.lan:/srv/restic/stonerspots
  export RESTIC_PASSWORD_FILE=/root/.restic-password
  mkdir -p -m 0700 /var/backups/stonerspots
  mariadb-dump --single-transaction --routines --triggers stonerspots \
    | gzip > /var/backups/stonerspots/db.sql.gz
  restic backup /var/backups/stonerspots /var/lib/stonerspots/uploads /etc/stonerspots
  restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
  ```

  The dump holds email addresses and password hashes: keep it encrypted,
  and try a restore now and then.
- **fail2ban.** The API logs every 429 (rate limited) and 5xx response as
  one journal line, e.g.
  `429 POST "/api/v1/auth/login" 2ms ip=203.0.113.7 id=4f2a9c0e1b3d5a7c`
  (after Go's date and time). Wrong passwords are not logged one by one in
  this version; a client that keeps trying hits the login limit
  (10/min per IP) and then shows up as 429 lines. A filter for those:

  ```ini
  # /etc/fail2ban/filter.d/stonerspots.conf
  [Definition]
  failregex = ^.* 429 POST "/api/v1/auth/(login|register|refresh)" \S+ ip=<HOST> id=\S+$
  journalmatch = _SYSTEMD_UNIT=stonerspots-backend.service

  # /etc/fail2ban/jail.d/stonerspots.local
  [stonerspots]
  enabled  = true
  backend  = systemd
  port     = http,https
  maxretry = 5
  findtime = 10m
  bantime  = 1h
  ```

  The `ip=` is the real client only with `trusted_proxies` set (else it is
  Caddy's 127.0.0.1, and fail2ban would ban nobody useful).
- **Automatic OS updates**: Debian/Ubuntu
  `sudo apt install unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades`,
  Fedora `dnf-automatic`. SSH with keys only (`PasswordAuthentication no`,
  `PermitRootLogin no`).
- **Memory.** The unit caps the API at `MemoryMax=1G` (with `GOMEMLIMIT`
  below it), so a flood of big uploads restarts the API instead of taking
  the database down. Change it with `sudo systemctl edit stonerspots-backend`:

  ```ini
  [Service]
  MemoryMax=2G
  Environment=GOMEMLIMIT=1700MiB
  ```

  and keep MariaDB away from the OOM killer (`sudo systemctl edit mariadb`,
  `[Service]` `OOMScoreAdjust=-500`).
- **Watch the logs** for bursts of 429 (someone scripting against the API)
  and 5xx (something broken), e.g. daily from cron:

  ```sh
  journalctl -u stonerspots-backend --since -24h -o cat | grep -cE '^\S+ \S+ 429 '
  journalctl -u stonerspots-backend --since -24h -o cat | grep -E '^\S+ \S+ 5[0-9]{2} '
  ```

  Updates from the admin page write their log to
  `/var/lib/stonerspots-update/status/log` (the admin page shows its end).
- **Admin page updates**: use "newest" (release), not dev, and set up
  [signed releases](#signed-releases) first.

## App updates

The Android, Windows, Linux and macOS apps look for a newer build on GitHub
at start (at most every 6 hours; Settings → Updates can switch that off) and
from Settings → Updates → "Check for updates". They ask the public GitHub API
without a token; when GitHub rate-limits them they wait quietly and use the
last answer. A newer build shows a banner: "Update now", "Later" (this
session) or "Skip this version". Web and iOS don't update themselves.

**Channels.** The build decides which releases it follows, with
`--dart-define=UPDATE_CHANNEL=…`:

- `dev` (what `dev-release.yml` builds): the newest `dev-<n>` prerelease, newer
  when `<n>` is above the app's build number (CI sets the build number to the
  run number, so `dev-63` is build 63).
- `release` (what `dev-release.yml` builds for a tag `vX.Y.Z`, see
  [Releasing 1.0](#releasing-10)): GitHub's latest regular release, asked for
  with `releases/latest` (so 30 dev builds after it don't push it out of
  sight). Only a tag of exactly the form `vX.Y.Z` counts (no `-rc1`, no
  missing `v`); it is newer when that version is above the app's version
  (`version:` in `pubspec.yaml`, without the build number). Its files are
  `stonerspots-vX.Y.Z-android.apk`, `…-linux-x64.tar.gz`, `…-windows-x64.zip`,
  `…-macos.zip`, signed through `SHA256SUMS-apps.txt` like the dev builds.
- not set (local `flutter run`/`build`): no update checks at all.

**Nothing unverified is installed.** CI lists the app files in
`SHA256SUMS-apps.txt` and signs it like the backend checksums (job
`sign-apps`, same key, namespace `stonerspots-release`). The app has the
public key compiled in and, before installing, checks that signature
(OpenSSH SSHSIG, ed25519), then that the downloaded file's SHA-256 is the one
in the signed list, and that the file is named after the release's own tag.
Downloads only come from `github.com` release URLs of this repository and
GitHub's asset hosts, over HTTPS. If the build has no key, the signature or
checksum doesn't match, or the app can't write to its folder, it installs
nothing and offers the release page instead.

Setup (once, with the key pair from [Signed releases](#signed-releases)):

1. Secret `RELEASE_SIGNING_KEY`: as described there.
2. Repository **variable** (not secret) `RELEASE_SIGNING_PUBKEY`: the public
   key line, e.g. `gh variable set RELEASE_SIGNING_PUBKEY < stonerspots-release.pub`.
   The builds pass it as `--dart-define=RELEASE_SIGNING_PUBKEY=…`.
3. Android signing key, so each APK installs over the previous one. Android
   only accepts an update signed with the same key as the installed app;
   without these secrets every CI build gets a throwaway debug key and the
   in-app update fails at the system installer:

   ```sh
   keytool -genkeypair -v -keystore stonerspots.jks -alias stonerspots \
     -keyalg RSA -keysize 4096 -validity 10000
   gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -w0 stonerspots.jks)
   gh secret set ANDROID_KEYSTORE_PASSWORD   # the store password
   gh secret set ANDROID_KEY_ALIAS --body stonerspots
   gh secret set ANDROID_KEY_PASSWORD        # the key password (or the store password)
   ```

   Keep the `.jks` and its passwords safe: losing them means users must
   uninstall and reinstall to get updates. Apps installed from earlier
   (debug-key) builds have to be reinstalled once. Dev builds and releases
   use the same key, so either installs over the other.

**Build numbers.** Every CI build, dev or release, gets the workflow's run
number as its build number (Android `versionCode`). Dev builds and releases
come from the same workflow, so that number only ever goes up: a release
installs over every APK built before it, a dev build over a release only if
it was built later. Android refuses a lower `versionCode`, so a phone with a
dev build newer than the release can only move to the release after
uninstalling (or with the next release). Renaming `dev-release.yml` would
restart the count at 1 and break every update: don't.

Per platform:

- **Android**: downloads the APK into the app's cache and opens the system
  installer, which asks for confirmation. The first time, Android asks to
  allow "Install unknown apps" for Stonerspots; the banner has a button to
  that setting.
- **Linux** (`.tar.gz` bundle): unpacks next to the app's folder, moves the
  old folder aside (`.<folder>.old`), moves the new one in, starts it and
  quits; the next start removes the old folder. Only if the user can write
  to the app's folder and the folder it is in; otherwise the release page.
- **Windows** (`.zip`): unpacks next to the app's folder; after the app quits
  a hidden PowerShell process swaps the folders (putting the old one back if
  that fails) and starts the new version. Same writability rule.
- **macOS** (`.zip` with `Stonerspots.app`, ad-hoc signed, not sandboxed):
  like Linux, for the `.app`. The app is not notarized, so Gatekeeper blocks
  the first start of a downloaded copy: right-click → Open (or
  `xattr -dr com.apple.quarantine Stonerspots.app`). Updates installed by the
  app itself don't get the quarantine flag.

The archives are unpacked with checks against `..`, absolute paths, links
(only inside the macOS bundle, never out of it) and oversized contents,
even though they are already verified by then.

## Releasing 1.0

Releases come from a tag `vX.Y.Z` on main. The tag push starts
`dev-release.yml` (the same workflow as the dev builds), which builds and
publishes the release; nothing else needs to be done by hand.

Once, before the first release:

1. **Release signing key**: secret `RELEASE_SIGNING_KEY` as in
   [Signed releases](#signed-releases) (steps 1-3), and the variable
   `RELEASE_SIGNING_PUBKEY` as in [App updates](#app-updates) (setup step 2).
2. **Android keystore** secrets `ANDROID_KEYSTORE_BASE64`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (and
   `ANDROID_KEY_PASSWORD` if it differs): [App updates](#app-updates), setup
   step 3. A release refuses to build without these and without the signing
   key (job "Check version").
3. **Pages from tags**: Settings → Environments → `github-pages` →
   Deployment branches and tags → add a rule for tags `v*`. Without it the
   last job ("Deploy web to /") fails with "not allowed to deploy to
   github-pages due to environment protection rules" (the release itself is
   published by then; start "Publish web app" from main by hand afterwards).
4. Recommended: a tag ruleset (Settings → Rules → Rulesets → New tag ruleset,
   target `v*`) that lets only you create, update or delete release tags.
   Whoever can push such a tag gets a signed release.

For 1.0:

1. **Merge `v2` into `main`** (main has nothing v2 lacks, so it is a fast
   forward) and wait for the dev build of it to go green:

   ```sh
   git switch main && git pull
   git merge --ff-only v2
   git push origin main
   ```

2. **Version**: `app/pubspec.yaml` already says `version: 1.0.0+1`, and
   `CHANGELOG.md` has the 1.0.0 entry. For later releases: raise `X.Y.Z`
   there (leave `+1`: CI sets the build number), add a CHANGELOG entry,
   commit and push to main. The tag must equal that version, or the release
   stops at its first job.
3. **Tag** the commit on main and push the tag:

   ```sh
   git tag -a v1.0.0 -m "Stonerspots 1.0.0"
   git push origin v1.0.0
   ```

   If no run starts (or one must be repeated), start it by hand from main:
   Actions → "Dev build & release" → Run workflow, tag `v1.0.0`, or
   `gh workflow run dev-release.yml --ref main -f tag=v1.0.0`.

What the run makes: the regular release (not a prerelease) **Stonerspots
1.0.0** on the tag, with a short install section and GitHub's generated
notes, holding

- `stonerspots-backend-v1.0.0-linux-amd64.tar.gz`, `…-linux-arm64.tar.gz`
  and `SHA256SUMS.txt` + `SHA256SUMS.txt.sig` (backend),
- `stonerspots-v1.0.0-android.apk`, `-linux-x64.tar.gz`, `-windows-x64.zip`,
  `-macos.zip`, `-web.zip`, `-ios-unsigned.ipa` and `SHA256SUMS-apps.txt` +
  `SHA256SUMS-apps.txt.sig` (apps; all built with `UPDATE_CHANNEL=release`
  and the public key compiled in),
- build provenance for every file (`gh attestation verify <file> --repo
  devilAPI/stonerspots`),

and deploys its web build to https://devilapi.github.io/stonerspots/ (the
newest dev build stays at `/dev/`). Release apps update only to newer
releases, dev apps only to newer dev builds.

**Check the signature by hand** (with `stonerspots-release.pub` from your
password manager, or the `RELEASE_SIGNING_PUBKEY` line):

```sh
gh release download v1.0.0 --repo devilAPI/stonerspots --dir v1.0.0 && cd v1.0.0
printf 'stonerspots-release %s\n' "$(cat ../stonerspots-release.pub)" > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I stonerspots-release -n stonerspots-release \
  -s SHA256SUMS.txt.sig < SHA256SUMS.txt
ssh-keygen -Y verify -f allowed_signers -I stonerspots-release -n stonerspots-release \
  -s SHA256SUMS-apps.txt.sig < SHA256SUMS-apps.txt
sha256sum -c SHA256SUMS.txt SHA256SUMS-apps.txt
```

Both `ssh-keygen` lines must say `Good "stonerspots-release" signature`.

**Server**: an existing install switches with
`sudo /opt/stonerspots/install-backend.sh --release` (or admin page →
"Update backend to newest"); a new one with the one-liner from
[Install the backend](#install-the-backend-on-a-server). With
`/etc/stonerspots/release-signing.pub` in place it installs nothing
unsigned. A server on a dev build with newer migrations than the release
is refused (nothing changes); it stays on dev until the next release.

**Rollback**:

- *A release that is broken*: fix forward with the next patch version
  (`1.0.1`): Android can't install an older version over a newer one, so a
  rollback for apps is always a new, higher release. To stop further
  installs meanwhile, mark it a prerelease
  (`gh release edit v1.0.0 --prerelease`): apps and `install-backend.sh
  --release` then see the previous release as the newest again; start
  "Publish web app" by hand to put the previous web build back on `/`.
  Don't delete or move a published tag.
- *A tag that failed before anything was published* (wrong version, missing
  key): delete it (`git push origin :refs/tags/v1.0.0 && git tag -d v1.0.0`),
  fix, tag again.
- *The backend*: an update whose service does not stay up goes back to
  `api.previous` by itself. By hand: `sudo systemctl stop
  stonerspots-backend`, `sudo cp -p /opt/stonerspots/api.previous
  /opt/stonerspots/api`, write the old tag into `/opt/stonerspots/VERSION`,
  start it again. The newer migrations stay (the database can't go back
  without a backup), which the older binary accepts.

## Web app on GitHub Pages

The `Publish web app` workflow deploys the web build of the newest release
(the highest `vX.Y.Z`) to https://devilapi.github.io/stonerspots/ and of the
newest dev build to `/dev/`; before the first release the root shows the dev
build too. `dev-release.yml` runs it after every dev build and every release.
For it to reach a backend:

- repository secret `API_URL`: public **HTTPS** URL of the API, e.g.
  `https://api.example.com/api/v1` (compiled into every build, so it is public)
- backend `allowed_origins: [https://devilapi.github.io]` (CORS) and
  `public_base_url` set to the backend's HTTPS origin so photo URLs work, in its
  `config.yaml` (or the env vars `ALLOWED_ORIGINS` / `PUBLIC_BASE_URL`)

The database credentials are only ever set on the backend server (its
`config.yaml`), never in the app or its build.

## Legal pages

The app has an Impressum (legal notice), a privacy policy
(Datenschutzerklärung) and community rules (Nutzungsregeln): in Settings →
Legal, under the login and registration forms, and on the web as
`https://devilapi.github.io/stonerspots/#/legal/imprint` (`…/privacy`,
`…/rules`; `…/stonerspots/legal/imprint/` forwards there, for links from
outside). Profile → menu → "Download my data" gives every user a JSON copy of
what the server stores about them (`GET /api/v1/me/export`, 3 a day).

**Nothing personal is stored in git or compiled into the app.** The operator
details come from the server, `GET /api/v1/legal`, which reads the `legal:`
section of `/etc/stonerspots/config.yaml`:

```yaml
legal:
  operator_name: "Your Name"
  address: |
    c/o <Impressum / address service>
    <street and number>
    <postcode> <town>
  email: "contact@your-domain"
  phone: ""                    # optional
  responsible_person: ""       # optional, § 18 Abs. 2 MStV; default operator_name
  country: "Deutschland"       # optional
  privacy_contact_email: ""    # optional, default email
  extra: ""                    # optional free text
```

§ 5 DDG needs an address where documents can be served: a c/o address of an
Impressum or address service works, a PO box does not. Until name, address
and email are set (example.org addresses do not count), the pages say the
operator has not set this up yet, and the API logs a warning at start. Then
`sudo systemctl restart stonerspots-backend`.

Before launch:

- **Review the privacy text** in
  [`app/lib/features/legal/privacy_text.dart`](app/lib/features/legal/privacy_text.dart)
  (German and English; the rules are in `rules_text.dart`). It is a template
  written from what the code does, not legal advice. Change the version date
  at the top of the file with every edit, and keep it in step with the code
  (new third parties, new data).
- **Log retention**: the text says the API's log lines (429, 5xx, admin 2FA
  failures, with IP addresses) live in journald and the reverse proxy may log
  requests. Limit both, e.g. `MaxRetentionSec=14day` in
  `/etc/systemd/journald.conf` and `roll_keep_for 336h` in Caddy's `log`
  block, and then name the period in the text.
- **Web app and Google**: the Flutter web build loads fonts and its CanvasKit
  engine from `fonts.gstatic.com` / `www.gstatic.com`; the privacy text says
  so. To avoid it, build with `--no-web-resources-cdn` and serve the fallback
  fonts yourself (`fontFallbackBaseUrl` in the Flutter loader config), then
  remove that sentence.

## Map tiles

- Light theme: OpenStreetMap standard tiles (fine for development, not for heavy
  production traffic).
- Dark theme: CARTO Dark Matter, needs a free key from
  <https://carto.com/basemaps/apikey>, passed as `CARTO_KEY`. Without a key the
  app falls back to the OpenStreetMap tiles. The key is visible in the built app;
  restrict it in CARTO's dashboard.
- Public transport map (lines and stops, worldwide, the third step of the
  map-type button): with a key from <https://manage.thunderforest.com> (free
  hobby plan: 150,000 tiles a month), passed as `THUNDERFOREST_KEY`,
  Thunderforest Transport (dark or light like the theme; the key is visible
  in the built app). Without a key the app uses ÖPNVKarte
  (<https://www.öpnvkarte.de>, tiles by memomaps.de, CC BY-SA, light style
  only, up to zoom 18), so the transport map is always there.
- Satellite previews: Esri World Imagery. Check CARTO's and Esri's terms before
  a commercial launch.

Map data © OpenStreetMap contributors.

## Verbotszonen

The map can show where § 5 KCanG (Germany) forbids consuming cannabis, and
spots say whether they lie in such a zone. Zones exist only in Germany:
elsewhere the map says so, spots have no zone status and adding one gives no
warning (see "Germany only" below).

- within sight of schools, children's and youth facilities, public
  playgrounds and public sports facilities. The law takes "within sight" as
  given within 100 m of the entrance area; like bubatzkarte, the app draws
  100 m around the whole site (red);
- pedestrian zones between 7 and 20 h German time (yellow while forbidden,
  green outside those hours; computed from UTC with the EU summer-time rule,
  so the device's time zone does not matter);
- places tagged `smoking:cannabis=no` (the place itself, 15 m around a point).

How it works:

- `GET /api/v1/zones?south=&west=&north=&east=` (public, own per-IP limit
  `limits.zones`, boxes up to 0.05° × 0.08°, larger ones get 400) answers with
  the places and their geometry (`[lat, lon]` arrays, simplified to 2 m).
  The 100 m buffer is drawn and checked by the app.
- The server asks Overpass by 0.02° tile with one query per tile (OSM tags:
  `amenity=school|kindergarten|childcare`, `building=kindergarten`,
  `amenity=social_facility` + `social_facility:for=child|juvenile|childcare`,
  `amenity=community_centre` + `community_centre=youth_centre`,
  `leisure=playground`, `leisure=pitch|sports_centre|sports_hall|stadium|track|
  swimming_pool|water_park|horse_riding|golf_course` (not `access=private|no`),
  `smoking:cannabis=no`, `highway=pedestrian` ways and areas). At most two
  queries run at once; each tile is cached for 7 days in memory and in the
  `zone_tiles` table, so a restart does not refetch. When Overpass fails, the
  last copy is served with `"stale": true`. A tile that is still being
  fetched, or waits for one of the two slots, is answered with 503
  `zones_pending` (the app asks again every 10 s); one that failed upstream is
  not asked for again for a minute, and the app retries it after 60 s while
  it is in view. Only the query goes upstream,
  with a User-Agent naming the project and `public_base_url`; never client
  addresses or user data. A dense city tile (central Munich) is about 280 kB
  from Overpass and 77 kB of JSON (13 kB gzipped) to the app.
- The app asks by the same tiles (deduplicated, cached for the session), only
  from zoom 15 on, and keeps each tile's shapes as ready-made paths, so a
  frame only transforms and fills them. A spot's status needs the tile it is
  in (plus a neighbour near a tile edge).
- The first time zones would show, the app explains their limits (OSM data
  can be incomplete or wrong; 100 m around the whole site is only an
  approximation; clubs, minors, state and municipal bans and other
  countries' laws are not covered; no legal advice).
  Cancelling turns the zones off; the button on the map turns them on again.
- Adding a spot in a zone shows a warning first, but never blocks (OSM can be
  wrong).
- Germany only: backend and app share Germany's border (OSM relation 51477,
  simplified to 20 m, about 58 kB as encoded polylines), embedded in
  `backend/internal/zones/germany_border.txt` and
  `app/lib/features/zones/germany_border.g.dart`. The server never asks
  Overpass for a tile outside Germany and drops places outside Germany from
  tiles the border runs through (a site that crosses it counts); the app
  does not request those tiles. Both files come from `backend/cmd/germanyborder`
  (usage in its header), and a backend test fails when they differ.

Config (`config.yaml`, env in brackets):

```yaml
zones:
  enabled: true        # [ZONES_ENABLED]; false: GET /zones answers 404
  overpass_url: "https://overpass-api.de/api/interpreter"   # [ZONES_OVERPASS_URL]
limits:
  zones: { n: 120, per: "1m" }   # per client IP
```

Data © OpenStreetMap contributors, under the ODbL; the map credits it while
the zones show. The idea comes from [bubatzkarte.de](https://bubatzkarte.de)
and [kifferkarte](https://github.com/Y0ngg4n/kifferkarte), thanks to both.
Stonerspots' implementation is its own (no code taken from either).
