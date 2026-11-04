#!/usr/bin/env bash
# Installs or updates the Stonerspots backend as a systemd service.
#
#   curl -fsSL https://raw.githubusercontent.com/devilAPI/stonerspots/main/install-backend.sh | sudo bash
#   sudo ./install-backend.sh            # install, or update an existing install
#   sudo ./install-backend.sh --dev      # newest dev build (dev-<n>)
#   sudo ./install-backend.sh --release  # switch a dev install to releases
#
# An existing install is detected and updated in place: it stays on its
# channel (release or dev), is skipped when already up to date, keeps
# config.yaml and the uploads untouched, and is only restarted if it was
# running. The previous api binary is kept as api.previous, and an update
# whose service does not stay up goes back to it by itself.
#
# Layout:
#   /opt/stonerspots/                         api, makeadmin, migrations/ (replaced on update)
#   /etc/stonerspots/config.yaml              settings; created once, never overwritten
#   /etc/stonerspots/release-signing.pub      optional: public key the downloads must be signed with
#   /var/lib/stonerspots/                     the service's own folder (systemd StateDirectory)
#   /var/lib/stonerspots/uploads/             uploaded photos (created by the API)
#   /var/lib/stonerspots-update/              update requests from the admin page
#   /etc/systemd/system/stonerspots-backend.service
#   /etc/systemd/system/stonerspots-update.{path,service}
#
# Updates from the admin page: the API (unprivileged) writes the wanted
# channel to /var/lib/stonerspots-update/request/channel. The root unit
# stonerspots-update.path notices it and runs update-backend.sh, which runs
# this script (installed as /opt/stonerspots/install-backend.sh) with
# --release or --dev and reports to /var/lib/stonerspots-update/status/.
#
# Rule for everything that runs as root here: never create, change, copy or
# remove anything by name inside a folder the service user can write to
# (/var/lib/stonerspots, .../request). The service user could have swapped
# any name in there for a link to a file of root's. Such folders are left to
# systemd (StateDirectory=) or handled with the service user's rights.
#
# The database itself (MariaDB 11.4) is not installed; point config.yaml at it.
set -euo pipefail
# Everything installed under /opt must be readable by the service user,
# whatever umask the caller has (the admin-page updater runs with 027).
umask 022

REPO="${STONERSPOTS_REPO:-devilAPI/stonerspots}"
INSTALL_DIR=/opt/stonerspots
CONFIG_DIR=/etc/stonerspots
DATA_DIR=/var/lib/stonerspots
UPDATE_DIR=/var/lib/stonerspots-update
SERVICE=stonerspots-backend
UPDATER=stonerspots-update
SERVICE_USER=stonerspots
UNIT_FILE="/etc/systemd/system/${SERVICE}.service"
# How long a restarted service must stay up to count as started: longer than
# the unit's RestartSec, so that a crash loop is seen between two attempts.
STARTUP_SECONDS=12
# Release signatures (see README, "Signed releases"): CI signs SHA256SUMS.txt
# with ssh-keygen -Y sign; with this public key present, nothing unsigned is
# installed or run.
SIGNING_KEY="$CONFIG_DIR/release-signing.pub"
SIGNING_NAMESPACE=stonerspots-release
SIGNING_KEY_OWNER=0
# Raised whenever the units below change, so that an install that is
# otherwise up to date still gets them on the next run.
UNITS_VERSION=2

usage() {
  cat <<EOF
Usage: $0 [--dev | --release] [--force]

Downloads the newest Stonerspots backend from github.com/${REPO} and installs
it as the systemd service ${SERVICE}. Run it again to update: an existing
install keeps its channel and its config.yaml.

  --dev       use the newest dev build (default for installs that have one)
  --release   use the newest release (default for new installs)
  --force     reinstall even when that version is already installed
  -h, --help  show this help
EOF
}

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() {
  printf '\n\033[1;33m!!! WARNING !!!\033[0m\n' >&2
  printf '    %s\n' "$@" >&2
  printf '\n' >&2
}

# verify_signature <SHA256SUMS.txt> <URL of SHA256SUMS.txt.sig> <work dir>
# Checks the CI signature of the checksum list against SIGNING_KEY. Without
# that key it only warns: the checksums alone prove a complete download,
# not who built it.
verify_signature() {
  local sums=$1 sig_url=$2 work=$3 line uid mode
  if [ ! -e "$SIGNING_KEY" ] && [ ! -L "$SIGNING_KEY" ]; then
    warn "No release signing key at ${SIGNING_KEY}." \
      "This download is checked for completeness only, NOT for who built it:" \
      "whoever can change the GitHub release can run code as root on this server." \
      "Set up the key as the README describes (\"Signed releases\")."
    return 0
  fi
  if [ -L "$SIGNING_KEY" ] || [ ! -f "$SIGNING_KEY" ]; then
    die "${SIGNING_KEY} must be a plain file, not a link"
  fi
  read -r uid mode < <(stat -c '%u %a' -- "$SIGNING_KEY")
  if [ "$uid" != "$SIGNING_KEY_OWNER" ] || [ $((8#$mode & 8#022)) -ne 0 ]; then
    die "${SIGNING_KEY} must belong to root and be writable by root only"
  fi
  command -v ssh-keygen >/dev/null || die "ssh-keygen (OpenSSH 8.2 or newer) is required to check the release signature"
  # Accepts a bare public key ("ssh-ed25519 AAAA... comment") as well as
  # allowed_signers lines ("stonerspots-release ssh-ed25519 AAAA...").
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) ;;
      ssh-* | ecdsa-* | sk-*)
        printf '%s namespaces="%s" %s\n' "$SIGNING_NAMESPACE" "$SIGNING_NAMESPACE" "$line" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$SIGNING_KEY" > "$work/allowed_signers"
  [ -s "$work/allowed_signers" ] || die "${SIGNING_KEY} holds no key"
  curl -fsSL -o "$work/SHA256SUMS.txt.sig" "$sig_url" \
    || die "this build is not signed (no SHA256SUMS.txt.sig), but ${SIGNING_KEY} requires a signature; nothing was installed"
  ssh-keygen -Y verify -f "$work/allowed_signers" -I "$SIGNING_NAMESPACE" -n "$SIGNING_NAMESPACE" \
    -s "$work/SHA256SUMS.txt.sig" < "$sums" >/dev/null 2>&1 \
    || die "the signature of SHA256SUMS.txt does not match ${SIGNING_KEY}; nothing was installed"
  log "Release signature checked against ${SIGNING_KEY}"
}

# The update runner (installed as $INSTALL_DIR/update-backend.sh). Its paths
# are the constants at the top of this script.
update_runner() {
  cat <<'RUNNER'
#!/usr/bin/env bash
# Runs a backend update the admin page asked for. Started as root by
# stonerspots-update.service when the request file appears; written by
# install-backend.sh.
#
# request/ belongs to the API user, who may have put anything there: a link
# to a file of root's, a FIFO, a folder. So root never opens, follows or
# removes anything in it with root's rights: the request is read (at most 16
# bytes, for at most 5 seconds) and then removed as the API user, and only
# the exact words "release" or "dev" are acted on.
set -uo pipefail
umask 027
req=/var/lib/stonerspots-update/request/channel
status=/var/lib/stonerspots-update/status
api_user=stonerspots
if [ "$(id -u)" -eq 0 ]; then
  as_api() { setpriv --reuid="$api_user" --regid="$api_user" --clear-groups --no-new-privs -- "$@"; }
else
  as_api() { "$@"; } # not root (tests): there are no rights to drop
fi
[ -e "$req" ] || [ -L "$req" ] || exit 0
channel=""
if [ -f "$req" ] && [ ! -L "$req" ]; then
  # NUL bytes become "?" so they cannot vanish from the comparison below
  channel=$(as_api timeout 5 head -c 16 -- "$req" 2>/dev/null | tr '\000' '?')
fi
# whatever it was, it goes (else the path unit fires again and again)
as_api rm -rf -- "$req"
case "$channel" in
  release | dev) ;;
  *) echo "ignoring update request: not a known channel" >&2; exit 0 ;;
esac
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
from=$(cat /opt/stonerspots/VERSION 2>/dev/null || true)
started=$(now)
state() { # state <running|done|failed> [to] [finished]
  printf 'state=%s\nchannel=%s\nfrom=%s\nto=%s\nstarted=%s\nfinished=%s\n' \
    "$1" "$channel" "$from" "${2:-}" "$started" "${3:-}" > "$status/state.new"
  mv -f "$status/state.new" "$status/state"
}
state running
# the installer gets the usual umask: the service user must read its files
if (umask 022 && exec /opt/stonerspots/install-backend.sh "--$channel") > "$status/log" 2>&1; then
  result=done
else
  result=failed
fi
state "$result" "$(cat /opt/stonerspots/VERSION 2>/dev/null || true)" "$(now)"
RUNNER
}

# The API's unit. It belongs to this script and is rewritten on every run;
# local changes go into a drop-in (systemctl edit stonerspots-backend).
api_unit() {
  cat <<EOF
# stonerspots-units: ${UNITS_VERSION}
# Written by install-backend.sh on every update; put local changes into a
# drop-in: systemctl edit ${SERVICE}
[Unit]
Description=Stonerspots backend API
Documentation=https://github.com/${REPO}
After=network-online.target mariadb.service
Wants=network-online.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
Environment=CONFIG_FILE=${CONFIG_DIR}/config.yaml
Environment=UPDATE_DIR=${UPDATE_DIR}
ExecStart=${INSTALL_DIR}/api
Restart=on-failure
RestartSec=5s

# ${DATA_DIR}, made and kept owned by ${SERVICE_USER} by systemd (the API
# creates uploads/ in it itself)
StateDirectory=${DATA_DIR#/var/lib/}
StateDirectoryMode=0750
UMask=0077

# Resources: a flood of large uploads kills only this service (and systemd
# restarts it), never the database next to it. GOMEMLIMIT makes Go collect
# garbage harder before that point.
MemoryMax=1G
Environment=GOMEMLIMIT=850MiB
TasksMax=512
LimitNOFILE=8192

# Sandbox. No MemoryDenyWriteExecute: AVIF decoding compiles WebAssembly
# to machine code at run time.
NoNewPrivileges=true
CapabilityBoundingSet=
AmbientCapabilities=
ProtectSystem=strict
ReadWritePaths=${UPDATE_DIR}/request
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectProc=invisible
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF
}

updater_path_unit() {
  cat <<EOF
# stonerspots-units: ${UNITS_VERSION}
[Unit]
Description=Stonerspots backend update requests from the admin page

[Path]
PathExists=${UPDATE_DIR}/request/channel

[Install]
WantedBy=paths.target
EOF
}

# Runs as root: it installs files and restarts services. It is sandboxed as
# far as that allows: it writes only where an update writes.
updater_service_unit() {
  cat <<EOF
# stonerspots-units: ${UNITS_VERSION}
[Unit]
Description=Stonerspots backend update (asked for on the admin page)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/update-backend.sh
# a stuck download or a request that hangs must not block updates forever
TimeoutStartSec=20min
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=-${INSTALL_DIR} -${CONFIG_DIR} -${UPDATE_DIR} -/etc/systemd/system
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
SystemCallArchitectures=native
EOF
}

# addr_listens_everywhere <config.yaml>: true when its addr: has no host
# (":8080", "0.0.0.0:8080", "[::]:8080") or there is no addr: at all.
addr_listens_everywhere() {
  local addr
  addr=$(sed -n 's/^addr:[[:space:]]*["'\'']\{0,1\}\([^"'\''#[:space:]]*\).*/\1/p' "$1" | head -n1)
  case "$addr" in
    '' | :* | 0.0.0.0:* | '[::]:'*) return 0 ;;
  esac
  return 1
}

# pick_backend_url <dev|release> <arch>: the download URL of the backend
# tarball for <arch> in a GitHub API answer on stdin (a release list, or the
# one release of releases/latest). The first match wins; the API lists the
# newest first. Only a file named exactly stonerspots-backend-<tag>-linux-<arch>.tar.gz
# in the download folder of that same tag counts, so a file named after
# another tag can't be passed off as this one. Tags: dev-<n> (dev builds,
# prereleases) or vX.Y.Z (releases).
pick_backend_url() {
  local channel=$1 arch=$2 tag_re url tag
  case "$channel" in
    dev) tag_re='^dev-[0-9]+$' ;;
    release) tag_re='^v[0-9]+\.[0-9]+\.[0-9]+$' ;;
    *) return 1 ;;
  esac
  while IFS= read -r url; do
    case "$url" in
      "https://github.com/${REPO}/releases/download/"*) ;;
      *) continue ;;
    esac
    tag=$(basename "$(dirname "$url")")
    [[ "$tag" =~ $tag_re ]] || continue
    [ "$(basename "$url")" = "stonerspots-backend-${tag}-linux-${arch}.tar.gz" ] || continue
    printf '%s\n' "$url"
    return 0
  done < <(grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4)
  return 1
}

# newest_migration <migrations dir>: the number of its newest *.up.sql
# (0 when there is none). The API refuses to start on a database that is
# newer than its migrations, so this tells whether an install would go back.
newest_migration() {
  local f n newest=0
  for f in "$1"/*.up.sql; do
    [ -e "$f" ] || continue
    n=$(basename "$f")
    n=${n%%_*}
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    n=$((10#$n))
    [ "$n" -gt "$newest" ] && newest=$n
  done
  echo "$newest"
}

# Sourced (by the tests): stop here, with the functions defined.
(return 0 2>/dev/null) && return 0

channel=""
force=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dev) channel=dev ;;
    --release) channel=release ;;
    --force) force=true ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "run as root (sudo $0)"
for cmd in curl tar sha256sum; do
  command -v "$cmd" >/dev/null || die "$cmd is required"
done

case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) die "unsupported architecture: $(uname -m) (builds exist for amd64 and arm64)" ;;
esac

# An existing install: its version, and its channel unless one was given.
installed=""
if [ -x "$INSTALL_DIR/api" ]; then
  installed=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo unknown)
  log "Found an existing install: ${installed} in ${INSTALL_DIR}"
  if [ -z "$channel" ]; then
    case "$installed" in
      dev-*) channel=dev ;;
      *) channel=release ;;
    esac
  fi
fi
[ -n "$channel" ] || channel=release
dev=false
[ "$channel" = dev ] && dev=true

api() { curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO}/$1"; }

# The backend tarball for this architecture: dev builds are the prereleases
# dev-<n>, releases the regular releases vX.Y.Z (GitHub's "latest").
if $dev; then
  log "Looking for the newest dev build (linux-${arch})"
  answer=$(api "releases?per_page=100") || die "cannot reach the GitHub API"
else
  log "Looking for the newest release (linux-${arch})"
  answer=$(api "releases/latest" 2>/dev/null) || die "no release published yet (use --dev for the newest dev build)"
fi
url=$(printf '%s' "$answer" | pick_backend_url "$channel" "$arch" || true)
[ -n "$url" ] || die "no backend build for linux-${arch} found in the $($dev && echo 'dev builds' || echo 'newest release')"
tag=$(basename "$(dirname "$url")")
file=$(basename "$url")

# (an install from before the admin-page updater still gets its units, and
# a service that fails to start is repaired by installing again)
svc_state=$(systemctl show -p ActiveState --value "$SERVICE" 2>/dev/null || true)
if [ "$installed" = "$tag" ] && ! $force && [ -f "/etc/systemd/system/${UPDATER}.path" ] \
  && grep -qx "# stonerspots-units: ${UNITS_VERSION}" "$UNIT_FILE" 2>/dev/null \
  && { [ "$svc_state" = active ] || [ "$svc_state" = inactive ]; }; then
  log "${tag} is already installed; nothing to do (use --force to reinstall)."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log "Downloading ${file}"
curl -fsSL -o "$tmp/$file" "$url"
curl -fsSL -o "$tmp/SHA256SUMS.txt" "$(dirname "$url")/SHA256SUMS.txt"
# Signature first, then the checksum, then unpacking: nothing from the
# download is opened, let alone run, before both passed.
verify_signature "$tmp/SHA256SUMS.txt" "$(dirname "$url")/SHA256SUMS.txt.sig" "$tmp"
(cd "$tmp" && grep -E " \*?${file}\$" SHA256SUMS.txt | sha256sum -c --quiet -) \
  || die "checksum of ${file} does not match SHA256SUMS.txt"

tar -xzf "$tmp/$file" -C "$tmp"
src="$tmp/${file%.tar.gz}"
[ -x "$src/api" ] || die "archive does not contain the api binary"

# Never back to a build with older migrations than the installed one (e.g.
# from a dev build to a release made before it): the database may have them
# applied already, and the older API would refuse to start on it.
if [ -d "$INSTALL_DIR/migrations" ]; then
  have=$(newest_migration "$INSTALL_DIR/migrations")
  want=$(newest_migration "$src/migrations")
  if [ "$want" -lt "$have" ]; then
    die "${tag} has database migrations up to ${want}, the installed ${installed:-version} up to ${have}," \
      "and the database can't go back. Nothing was changed; keep the installed build until a newer ${channel} build is out."
  fi
fi

# An update from the admin page runs the installed copy of this script, which
# is the one from the last update. Hand over to the copy in the archive, so a
# fix to this script already applies to the update that delivers it. (That
# copy was checked above, and checks the download again itself.)
if [ "${BASH_SOURCE[0]:-}" = "$INSTALL_DIR/install-backend.sh" ] && [ -z "${STONERSPOTS_HANDED_OVER:-}" ] \
  && [ -f "$src/install-backend.sh" ] && ! cmp -s "$src/install-backend.sh" "${BASH_SOURCE[0]}"; then
  log "Continuing with the installer of ${tag}"
  next_args=("--${channel}")
  if $force; then next_args+=(--force); fi
  STONERSPOTS_HANDED_OVER=1 bash "$src/install-backend.sh" "${next_args[@]}"
  exit 0
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  log "Creating system user ${SERVICE_USER}"
  useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

if [ -n "$installed" ]; then
  log "Updating ${installed} -> ${tag} in ${INSTALL_DIR}"
else
  log "Installing ${tag} to ${INSTALL_DIR}"
fi
# root's: the service user must never be able to change what root runs
install -d -m 0755 -o root -g root "$INSTALL_DIR"
# Remember whether the service should run: an update restarts only those. A
# failed or crash-looping service counts, or installing again would not repair it.
was_running=false
case "$svc_state" in
  active | activating | deactivating | reloading | failed) was_running=true ;;
esac
# keep the old binary for a manual rollback
if [ -x "$INSTALL_DIR/api" ]; then
  cp -p "$INSTALL_DIR/api" "$INSTALL_DIR/api.previous"
fi
rm -rf "$INSTALL_DIR/migrations"
cp -R "$src/migrations" "$INSTALL_DIR/"
# also repairs installs whose files were made unreadable by an earlier
# admin-page update (the service user must read them)
chmod -R u=rwX,go=rX "$INSTALL_DIR/migrations"
for f in config.example.yaml schema.example.sql; do
  [ -f "$src/$f" ] && install -m 0644 "$src/$f" "$INSTALL_DIR/$f"
done
install -m 0755 "$src/makeadmin" "$INSTALL_DIR/makeadmin"
# This script and the update runner may be running right now (an update
# from the admin page): replace them by rename, never in place, so the
# running copy keeps reading its old file.
put_script() { # put_script <dest>, content on stdin
  cat > "$1.new" && chmod 0755 "$1.new" && mv -f "$1.new" "$1"
}
if [ -f "$src/install-backend.sh" ]; then
  put_script "$INSTALL_DIR/install-backend.sh" < "$src/install-backend.sh"
elif [ -f "${BASH_SOURCE[0]:-}" ]; then
  # older archives lack it: the copy being run (not there when piped from curl)
  put_script "$INSTALL_DIR/install-backend.sh" < "${BASH_SOURCE[0]}"
fi
update_runner | put_script "$INSTALL_DIR/update-backend.sh"
# install via a temp name + rename so a running process keeps its old binary
install -m 0755 "$src/api" "$INSTALL_DIR/api.new" && mv -f "$INSTALL_DIR/api.new" "$INSTALL_DIR/api"
echo "$tag" > "$INSTALL_DIR/VERSION"
chmod 0644 "$INSTALL_DIR/VERSION"

# The data folder (/var/lib/stonerspots) is systemd's to create and own
# (StateDirectory= in the unit), and the API makes uploads/ in it itself:
# root does nothing inside it, see the rule at the top.
#
# The update folder is root's, so nothing in it can be swapped by the
# service user: only request/ is theirs (and it is only ever touched as a
# whole, by its fixed name in this root-owned folder). setgid makes the
# runner's status files readable for their group.
install -d -m 0750 -o root -g "$SERVICE_USER" "$UPDATE_DIR"
install -d -m 2750 -o root -g "$SERVICE_USER" "$UPDATE_DIR/status"
install -d -m 0700 -o "$SERVICE_USER" -g "$SERVICE_USER" "$UPDATE_DIR/request"
install -d -m 0750 -o root -g "$SERVICE_USER" "$CONFIG_DIR"

first_install=false
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
  first_install=true
  log "Creating ${CONFIG_DIR}/config.yaml"
  secret=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  sed -e "s|^jwt_secret: .*|jwt_secret: \"${secret}\"|" \
      -e "s|^upload_dir: .*|upload_dir: \"${DATA_DIR}/uploads\"|" \
      -e "s|^migrations_dir: .*|migrations_dir: \"${INSTALL_DIR}/migrations\"|" \
      "$INSTALL_DIR/config.example.yaml" > "$CONFIG_DIR/config.yaml"
  # readable by the service, not by other users: holds the DB password and JWT secret
  chown root:"$SERVICE_USER" "$CONFIG_DIR/config.yaml"
  chmod 0640 "$CONFIG_DIR/config.yaml"
else
  log "Keeping ${CONFIG_DIR}/config.yaml"
  # Settings added in newer versions: report them, never edit the file.
  missing=""
  while read -r key; do
    grep -qE "^${key}" "$CONFIG_DIR/config.yaml" || missing="${missing} ${key%:}"
  done < <(grep -oE '^[a-z_]+:' "$INSTALL_DIR/config.example.yaml" 2>/dev/null || true)
  if [ -n "$missing" ]; then
    log "Settings your config.yaml does not set (their defaults apply):${missing}"
    echo "  see ${INSTALL_DIR}/config.example.yaml"
  fi
  if addr_listens_everywhere "$CONFIG_DIR/config.yaml"; then
    log "Hint: ${CONFIG_DIR}/config.yaml listens on all interfaces (addr)."
    echo "  Behind a reverse proxy on this machine (recommended, see the README) set"
    echo "    addr: \"127.0.0.1:8080\""
    echo "    trusted_proxies: [\"127.0.0.1/32\", \"::1/128\"]"
    echo "  so that clients cannot skip the proxy and rate limits apply per client."
  fi
fi

if ! command -v systemctl >/dev/null || [ ! -d /run/systemd/system ]; then
  # Without systemd nobody else makes the data folder. Only a missing one is
  # made; /var/lib is root's, so the service user cannot have put a link here.
  [ -d "$DATA_DIR" ] || install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_USER" "$DATA_DIR"
  log "$([ -n "$installed" ] && echo Updated to || echo Installed) ${tag}, but systemd is not running here; start it by hand:"
  echo "  cd ${INSTALL_DIR} && sudo -u ${SERVICE_USER} CONFIG_FILE=${CONFIG_DIR}/config.yaml ./api"
  exit 0
fi

# Units are rewritten on every run (UNITS_VERSION); local changes belong in
# drop-ins (systemctl edit <unit>), which stay.
log "Writing ${UNIT_FILE}"
# kept for the way back below: if the service does not start, the old
# binary gets its old unit too
[ -f "$UNIT_FILE" ] && cp -p "$UNIT_FILE" "$tmp/unit.previous"
api_unit > "$UNIT_FILE"
log "Writing ${UPDATER}.path and ${UPDATER}.service (updates from the admin page)"
updater_path_unit > "/etc/systemd/system/${UPDATER}.path"
updater_service_unit > "/etc/systemd/system/${UPDATER}.service"
systemctl daemon-reload
systemctl enable --quiet "$SERVICE"
systemctl enable --now --quiet "${UPDATER}.path"

# A unit is active as soon as its process exists, so one good look proves
# nothing: the API fails on start only after it tried the migrations.
restart_and_check() {
  local _
  systemctl restart "$SERVICE" || return 1
  for _ in $(seq "$STARTUP_SECONDS"); do
    sleep 1
    systemctl is-active --quiet "$SERVICE" || return 1
  done
}

if $first_install || [ -z "$installed" ]; then
  log "Installed ${tag}. Next steps:"
  cat <<EOF
  1. Edit ${CONFIG_DIR}/config.yaml: database, public_base_url, allowed_origins.
     (The database must exist; the API creates the tables on start.)
     The API listens on 127.0.0.1:8080 only: put a reverse proxy with HTTPS in
     front of it (the README has a ready Caddyfile and a checklist for home servers).
  2. sudo systemctl start ${SERVICE}
  3. Check it: systemctl status ${SERVICE}   /   journalctl -u ${SERVICE} -f
  Make a user admin: cd ${INSTALL_DIR} && sudo -u ${SERVICE_USER} CONFIG_FILE=${CONFIG_DIR}/config.yaml ./makeadmin -email you@example.com
EOF
elif $was_running; then
  log "Restarting ${SERVICE}"
  systemctl reset-failed "$SERVICE" 2>/dev/null || true
  if restart_and_check; then
    log "Updated to ${tag}; ${SERVICE} is running."
  elif [ "$installed" != "$tag" ] && [ -x "$INSTALL_DIR/api.previous" ]; then
    log "${SERVICE} did not start on ${tag}; going back to ${installed}"
    # The new migrations stay: they may be applied already, and the old
    # binary refuses a database newer than its migrations folder.
    cp -p "$INSTALL_DIR/api.previous" "$INSTALL_DIR/api.new" && mv -f "$INSTALL_DIR/api.new" "$INSTALL_DIR/api"
    echo "$installed" > "$INSTALL_DIR/VERSION"
    if [ -f "$tmp/unit.previous" ] && ! cmp -s "$tmp/unit.previous" "$UNIT_FILE"; then
      cp "$tmp/unit.previous" "$UNIT_FILE"
      systemctl daemon-reload
    fi
    systemctl reset-failed "$SERVICE" 2>/dev/null || true
    restart_and_check || die "${SERVICE} does not start on ${installed} either; see: journalctl -u ${SERVICE} -n 50"
    die "${tag} did not start, back on ${installed}; see: journalctl -u ${SERVICE} -n 50"
  else
    die "${SERVICE} did not start; see: journalctl -u ${SERVICE} -n 50"
  fi
else
  log "Updated to ${tag}. ${SERVICE} was not running, so it stays stopped:"
  echo "  sudo systemctl start ${SERVICE}"
fi
