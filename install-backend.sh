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
# running. The previous api binary is kept as api.previous.
#
# Layout:
#   /opt/stonerspots/                         api, makeadmin, migrations/ (replaced on update)
#   /etc/stonerspots/config.yaml              settings; created once, never overwritten
#   /var/lib/stonerspots/uploads/             uploaded photos
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
# The database itself (MariaDB 11.4) is not installed; point config.yaml at it.
set -euo pipefail

REPO="${STONERSPOTS_REPO:-devilAPI/stonerspots}"
INSTALL_DIR=/opt/stonerspots
CONFIG_DIR=/etc/stonerspots
DATA_DIR=/var/lib/stonerspots
UPDATE_DIR=/var/lib/stonerspots-update
SERVICE=stonerspots-backend
UPDATER=stonerspots-update
SERVICE_USER=stonerspots
UNIT_FILE="/etc/systemd/system/${SERVICE}.service"

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

# Download URLs of backend tarballs for this architecture, newest release first.
if $dev; then
  log "Looking for the newest dev build (linux-${arch})"
  urls=$(api "releases?per_page=100") || die "cannot reach the GitHub API"
  pattern="/download/dev-[0-9]+/stonerspots-backend-dev-[0-9]+-linux-${arch}\.tar\.gz"
else
  log "Looking for the newest release (linux-${arch})"
  urls=$(api "releases/latest" 2>/dev/null) || die "no release published yet (use --dev for the newest dev build)"
  pattern="/stonerspots-backend-[^/\"]+-linux-${arch}\.tar\.gz"
fi
url=$(printf '%s' "$urls" | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 \
  | grep -E "$pattern" | head -n1 || true)
[ -n "$url" ] || die "no backend build for linux-${arch} found in the $($dev && echo 'dev builds' || echo 'newest release')"
tag=$(basename "$(dirname "$url")")
file=$(basename "$url")

# (an install from before the admin-page updater still gets its units)
if [ "$installed" = "$tag" ] && ! $force && [ -f "/etc/systemd/system/${UPDATER}.path" ]; then
  log "${tag} is already installed; nothing to do (use --force to reinstall)."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log "Downloading ${file}"
curl -fsSL -o "$tmp/$file" "$url"
curl -fsSL -o "$tmp/SHA256SUMS.txt" "$(dirname "$url")/SHA256SUMS.txt"
(cd "$tmp" && grep -E " \*?${file}\$" SHA256SUMS.txt | sha256sum -c --quiet -) \
  || die "checksum of ${file} does not match SHA256SUMS.txt"

tar -xzf "$tmp/$file" -C "$tmp"
src="$tmp/${file%.tar.gz}"
[ -x "$src/api" ] || die "archive does not contain the api binary"

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  log "Creating system user ${SERVICE_USER}"
  useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

if [ -n "$installed" ]; then
  log "Updating ${installed} -> ${tag} in ${INSTALL_DIR}"
else
  log "Installing ${tag} to ${INSTALL_DIR}"
fi
install -d -m 0755 "$INSTALL_DIR"
# remember whether the service runs now: an update restarts only a running one
was_running=false
if command -v systemctl >/dev/null && [ -d /run/systemd/system ] && systemctl is-active --quiet "$SERVICE"; then
  was_running=true
fi
# keep the old binary for a manual rollback
if [ -x "$INSTALL_DIR/api" ]; then
  cp -p "$INSTALL_DIR/api" "$INSTALL_DIR/api.previous"
fi
rm -rf "$INSTALL_DIR/migrations"
cp -R "$src/migrations" "$INSTALL_DIR/"
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
# The paths below are the constants at the top of this script.
put_script "$INSTALL_DIR/update-backend.sh" <<'RUNNER'
#!/usr/bin/env bash
# Runs a backend update the admin page asked for. Started as root by
# stonerspots-update.service when the request file appears; written by
# install-backend.sh. The request folder belongs to the API user, so the
# request is only read as one word, never followed or trusted further.
set -uo pipefail
umask 027
req=/var/lib/stonerspots-update/request/channel
status=/var/lib/stonerspots-update/status
[ -e "$req" ] || [ -L "$req" ] || exit 0
# anything but a plain file is dropped unread (else the unit fires forever);
# rm does not follow links
if [ -L "$req" ] || [ ! -f "$req" ]; then
  rm -rf "$req"
  exit 0
fi
channel=$(head -c 16 "$req" | tr -cd 'a-z')
rm -f "$req"
case "$channel" in
  release | dev) ;;
  *) echo "ignoring update request: unknown channel" >&2; exit 0 ;;
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
if /opt/stonerspots/install-backend.sh "--$channel" > "$status/log" 2>&1; then
  result=done
else
  result=failed
fi
state "$result" "$(cat /opt/stonerspots/VERSION 2>/dev/null || true)" "$(now)"
RUNNER
# install via a temp name + rename so a running process keeps its old binary
install -m 0755 "$src/api" "$INSTALL_DIR/api.new" && mv -f "$INSTALL_DIR/api.new" "$INSTALL_DIR/api"
echo "$tag" > "$INSTALL_DIR/VERSION"

install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_USER" "$DATA_DIR" "$DATA_DIR/uploads"
# Outside DATA_DIR on purpose: the API user owns that and could swap a
# folder in it for a link to where root writes. Here only request/ is
# theirs; setgid makes the runner's status files readable for their group.
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
fi

if ! command -v systemctl >/dev/null || [ ! -d /run/systemd/system ]; then
  log "$([ -n "$installed" ] && echo Updated to || echo Installed) ${tag}, but systemd is not running here; start it by hand:"
  echo "  cd ${INSTALL_DIR} && sudo -u ${SERVICE_USER} CONFIG_FILE=${CONFIG_DIR}/config.yaml ./api"
  exit 0
fi

# The unit belongs to this script and is rewritten on every run; put local
# changes into a drop-in (systemctl edit stonerspots-backend), which stays.
log "Writing ${UNIT_FILE}"
cat > "$UNIT_FILE" <<EOF
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

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
ReadWritePaths=${DATA_DIR} ${UPDATE_DIR}/request

[Install]
WantedBy=multi-user.target
EOF
log "Writing ${UPDATER}.path and ${UPDATER}.service (updates from the admin page)"
cat > "/etc/systemd/system/${UPDATER}.path" <<EOF
[Unit]
Description=Stonerspots backend update requests from the admin page

[Path]
PathExists=${UPDATE_DIR}/request/channel

[Install]
WantedBy=paths.target
EOF
cat > "/etc/systemd/system/${UPDATER}.service" <<EOF
[Unit]
Description=Stonerspots backend update (asked for on the admin page)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/update-backend.sh
EOF
systemctl daemon-reload
systemctl enable --quiet "$SERVICE"
systemctl enable --now --quiet "${UPDATER}.path"

if $first_install || [ -z "$installed" ]; then
  log "Installed ${tag}. Next steps:"
  cat <<EOF
  1. Edit ${CONFIG_DIR}/config.yaml: database, public_base_url, allowed_origins.
     (The database must exist; the API creates the tables on start.)
  2. sudo systemctl start ${SERVICE}
  3. Check it: systemctl status ${SERVICE}   /   journalctl -u ${SERVICE} -f
  Make a user admin: cd ${INSTALL_DIR} && sudo -u ${SERVICE_USER} CONFIG_FILE=${CONFIG_DIR}/config.yaml ./makeadmin -email you@example.com
EOF
elif $was_running; then
  log "Restarting ${SERVICE}"
  systemctl restart "$SERVICE"
  sleep 2
  if systemctl is-active --quiet "$SERVICE"; then
    log "Updated to ${tag}; ${SERVICE} is running."
  else
    echo "  the previous binary is ${INSTALL_DIR}/api.previous" >&2
    die "${SERVICE} did not start; see: journalctl -u ${SERVICE} -n 50"
  fi
else
  log "Updated to ${tag}. ${SERVICE} was not running, so it stays stopped:"
  echo "  sudo systemctl start ${SERVICE}"
fi
