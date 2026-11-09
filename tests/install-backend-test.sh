#!/usr/bin/env bash
# Tests for install-backend.sh that need neither root nor systemd nor the
# network: the update runner (in a temp folder with fake paths), the release
# signature check, the generated units and the config hint.
#
#   bash tests/install-backend-test.sh
#
# Needs ssh-keygen (OpenSSH 8.2+); uses systemd-analyze when there is one.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
installer="$here/../install-backend.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
check() { # check <name> <command...>
  local name=$1
  shift
  if "$@"; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    failures=$((failures + 1))
  fi
}
not() { ! "$@"; }

# Defines the installer's functions and constants, then stops (see the end
# of its function section).
# (shellcheck -x runs from the repository root, as in CI)
# shellcheck source=install-backend.sh
source "$installer"
set +e # the installer's set -e must not end the tests

# --- the installer never touches the service user's data folder as root ---

check "no root file operation inside DATA_DIR" \
  not grep -nE '^[[:space:]]*(install|chown|chmod|cp|mkdir|rm|mv|ln|touch)[[:space:]].*\$\{?DATA_DIR\}?/' "$installer"

# --- update runner -------------------------------------------------------

# runner_setup <name>: a fake update folder and install dir under $work, and
# the runner pointed at them. The fake installer records its arguments.
runner_setup() {
  root="$work/runner.$1"
  mkdir -p "$root/update/request" "$root/update/status" "$root/opt"
  printf 'dev-1\n' > "$root/opt/VERSION"
  printf '#!/usr/bin/env bash\necho "$*" >> %q\n' "$root/ran" > "$root/opt/install-backend.sh"
  chmod +x "$root/opt/install-backend.sh"
  update_runner | sed -e "s|/var/lib/stonerspots-update|$root/update|g" \
    -e "s|/opt/stonerspots|$root/opt|g" > "$root/runner.sh"
  req="$root/update/request/channel"
}
run_runner() { timeout 20 bash "$root/runner.sh" 2>/dev/null; }
ran() { [ "$(cat "$root/ran" 2>/dev/null)" = "$1" ]; }
ran_nothing() { [ ! -e "$root/ran" ]; }
request_gone() { [ ! -e "$req" ] && [ ! -L "$req" ]; }
state_is() { grep -qx "state=$1" "$root/update/status/state"; }
quick() { [ $((SECONDS - start)) -lt 10 ]; } # since $start

runner_setup release
printf 'release\n' > "$req"
run_runner
check "runner: release runs the installer with --release" ran --release
check "runner: release request is removed" request_gone
check "runner: release reports done" state_is 'done'

runner_setup dev
printf 'dev' > "$req"
run_runner
check "runner: dev (no newline) runs --dev" ran --dev

n=0
for bad in 'release; rm -rf /' 'releasex' 'Release' 'release\r\n' 'dev\0' 'release\nrelease' \
  'releasereleaserelease' '--force' ''; do
  n=$((n + 1))
  runner_setup "bad$n"
  # shellcheck disable=SC2059 # the cases are printf formats on purpose
  printf -- "$bad" > "$req"
  run_runner
  check "runner: '$bad' is ignored and removed" eval 'ran_nothing && request_gone'
done

runner_setup symlink
printf 'release\n' > "$root/secret"
ln -s "$root/secret" "$req"
run_runner
check "runner: a link is not followed" ran_nothing
check "runner: a link is removed, its target kept" eval 'request_gone && [ -f "$root/secret" ]'

runner_setup dir
mkdir -p "$req/sub"
printf 'release\n' > "$req/sub/x"
run_runner
check "runner: a folder is ignored and removed" eval 'ran_nothing && request_gone'

runner_setup fifo
mkfifo "$req"
start=$SECONDS
run_runner
check "runner: a FIFO does not hang it" quick
check "runner: a FIFO is ignored and removed" eval 'ran_nothing && request_gone'

# A FIFO swapped in between the check and the read: the read gives up.
runner_setup fifo-race
sed -i 's/^if \[ -f "\$req" \] && \[ ! -L "\$req" \]; then$/if true; then/' "$root/runner.sh"
check "runner: (test setup) the plain-file check could be skipped" grep -q '^if true; then$' "$root/runner.sh"
mkfifo "$req"
start=$SECONDS
run_runner
check "runner: a FIFO read times out within seconds" quick
check "runner: ... and that FIFO is ignored and removed" eval 'ran_nothing && request_gone'

runner_setup none
run_runner
check "runner: no request, nothing happens" eval 'ran_nothing && [ ! -e "$root/update/status/state" ]'

# --- release signature ---------------------------------------------------

sig="$work/sig"
mkdir -p "$sig/good" "$sig/other" "$sig/namespace" "$sig/unsigned"
ssh-keygen -q -t ed25519 -N '' -C release -f "$sig/key"
ssh-keygen -q -t ed25519 -N '' -C attacker -f "$sig/attacker"
printf '%s  stonerspots-backend-dev-7-linux-amd64.tar.gz\n' "$(printf x | sha256sum | cut -d' ' -f1)" > "$sig/SHA256SUMS.txt"
for d in good other namespace unsigned; do cp "$sig/SHA256SUMS.txt" "$sig/$d/"; done
ssh-keygen -q -Y sign -f "$sig/key" -n "$SIGNING_NAMESPACE" "$sig/good/SHA256SUMS.txt" 2>/dev/null
ssh-keygen -q -Y sign -f "$sig/attacker" -n "$SIGNING_NAMESPACE" "$sig/other/SHA256SUMS.txt" 2>/dev/null
ssh-keygen -q -Y sign -f "$sig/key" -n file "$sig/namespace/SHA256SUMS.txt" 2>/dev/null

# fake curl -fsSL -o <dest> <url>: serves the files of $served by name
curl() {
  local dest="" url=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -o) dest=$2; shift ;;
      -*) ;;
      *) url=$1 ;;
    esac
    shift
  done
  [ -f "$served/${url##*/}" ] && cp "$served/${url##*/}" "$dest"
}
SIGNING_KEY_OWNER=$(id -u) # the tests do not run as root

# verify <key file> <served dir> [sums]: runs the check like the installer
verify() {
  served=$2
  local out
  out=$(mktemp -d "$work/verify.XXXXXX")
  (SIGNING_KEY=$1 verify_signature "${3:-$served/SHA256SUMS.txt}" \
    "https://example.invalid/dev-7/SHA256SUMS.txt.sig" "$out") > "$out.log" 2>&1
}

cp "$sig/key.pub" "$sig/bare.pub"
printf '# release key\n%s namespaces="%s" %s\n' "$SIGNING_NAMESPACE" "$SIGNING_NAMESPACE" "$(cat "$sig/key.pub")" > "$sig/allowed.pub"
printf '%s %s\n' "$SIGNING_NAMESPACE" "$(cat "$sig/key.pub")" > "$sig/plain-allowed.pub"
cp "$sig/key.pub" "$sig/writable.pub"
chmod 0644 "$sig/bare.pub" "$sig/allowed.pub" "$sig/plain-allowed.pub"
chmod 0664 "$sig/writable.pub"
ln -s "$sig/bare.pub" "$sig/link.pub"
printf '# nothing here\n\n' > "$sig/empty.pub"
cp "$sig/SHA256SUMS.txt" "$sig/tampered.txt"
printf '%s  evil.tar.gz\n' "$(printf y | sha256sum | cut -d' ' -f1)" >> "$sig/tampered.txt"

check "signature: good, bare public key" verify "$sig/bare.pub" "$sig/good"
# a release's list, as sign-backend makes it for a tag vX.Y.Z
mkdir -p "$sig/release"
for a in amd64 arm64; do
  printf '%s  stonerspots-backend-v1.0.0-linux-%s.tar.gz\n' "$(printf '%s' "$a" | sha256sum | cut -d' ' -f1)" "$a"
done > "$sig/release/SHA256SUMS.txt"
ssh-keygen -q -Y sign -f "$sig/key" -n "$SIGNING_NAMESPACE" "$sig/release/SHA256SUMS.txt" 2>/dev/null
check "signature: a release's SHA256SUMS.txt (v1.0.0)" verify "$sig/bare.pub" "$sig/release"
check "signature: ... signed by another key, refused" not verify "$sig/bare.pub" "$sig/other" "$sig/release/SHA256SUMS.txt"
check "signature: good, allowed_signers line" verify "$sig/allowed.pub" "$sig/good"
check "signature: good, allowed_signers line without options" verify "$sig/plain-allowed.pub" "$sig/good"
check "signature: changed SHA256SUMS.txt is refused" not verify "$sig/bare.pub" "$sig/good" "$sig/tampered.txt"
check "signature: another key is refused" not verify "$sig/bare.pub" "$sig/other"
check "signature: another namespace is refused" not verify "$sig/bare.pub" "$sig/namespace"
check "signature: a missing signature is refused" not verify "$sig/bare.pub" "$sig/unsigned"
check "signature: a key file others can write is refused" not verify "$sig/writable.pub" "$sig/good"
check "signature: a key file that is a link is refused" not verify "$sig/link.pub" "$sig/good"
check "signature: a key file without a key is refused" not verify "$sig/empty.pub" "$sig/good"
check "signature: without a key file it goes on" verify "$sig/missing.pub" "$sig/unsigned"
check "signature: ... but warns" grep -q "NOT for who built it" "$(ls -t "$work"/verify.*.log | head -n1)"
unset -f curl

# --- which download (release asset names) ----------------------------------

gh_dl="https://github.com/${REPO}/releases/download"
# asset <tag> <file>: one asset entry the way the GitHub API prints it
asset() { printf '        "browser_download_url": "%s/%s/%s"\n' "$gh_dl" "$1" "$2"; }
# release <tag> [prerelease]: a release with every file the workflow publishes
release() {
  printf '  {\n    "tag_name": "%s",\n    "prerelease": %s,\n    "assets": [\n' "$1" "${2:-false}"
  for f in "stonerspots-backend-$1-linux-amd64.tar.gz" "stonerspots-backend-$1-linux-arm64.tar.gz" \
    SHA256SUMS.txt SHA256SUMS.txt.sig "stonerspots-$1-linux-x64.tar.gz" "stonerspots-$1-android.apk"; do
    asset "$1" "$f"
  done
  printf '    ]\n  }\n'
}
pick() { # pick <channel> <arch> <expected URL or ""> (answer on stdin)
  local got
  got=$(pick_backend_url "$1" "$2") || got=""
  [ "$got" = "$3" ] || { echo "      got: ${got:-nothing}, want: ${3:-nothing}" >&2; return 1; }
}

list=$(printf '[\n'; release dev-14 true; release v1.0.0; release dev-12 true; printf ']\n')
check "pick: dev takes the newest dev build" \
  pick dev amd64 "$gh_dl/dev-14/stonerspots-backend-dev-14-linux-amd64.tar.gz" <<<"$list"
check "pick: dev arm64" \
  pick dev arm64 "$gh_dl/dev-14/stonerspots-backend-dev-14-linux-arm64.tar.gz" <<<"$list"
check "pick: release passes over dev builds" \
  pick release amd64 "$gh_dl/v1.0.0/stonerspots-backend-v1.0.0-linux-amd64.tar.gz" <<<"$list"
latest=$(release v1.2.3)
check "pick: releases/latest (one object), amd64" \
  pick release amd64 "$gh_dl/v1.2.3/stonerspots-backend-v1.2.3-linux-amd64.tar.gz" <<<"$latest"
check "pick: releases/latest, arm64" \
  pick release arm64 "$gh_dl/v1.2.3/stonerspots-backend-v1.2.3-linux-arm64.tar.gz" <<<"$latest"
check "pick: a release is not a dev build" pick dev amd64 "" <<<"$latest"
check "pick: a dev build is not a release" pick release amd64 "" <<<"$(release dev-9 true)"
check "pick: no tarball for the architecture" pick release riscv64 "" <<<"$latest"
check "pick: v1.0.0-rc1 is not a release" pick release amd64 "" <<<"$(release v1.0.0-rc1)"
check "pick: 1.0.0 without v is not a release" pick release amd64 "" <<<"$(release 1.0.0)"
check "pick: a file named after another tag is skipped" pick release amd64 "" \
  <<<"$(asset v1.0.1 stonerspots-backend-v1.0.0-linux-amd64.tar.gz)"
check "pick: ... and the next good one taken" \
  pick dev amd64 "$gh_dl/dev-3/stonerspots-backend-dev-3-linux-amd64.tar.gz" \
  <<<"$(asset dev-4 stonerspots-backend-dev-2-linux-amd64.tar.gz; asset dev-3 stonerspots-backend-dev-3-linux-amd64.tar.gz)"
check "pick: only downloads from this repository" pick release amd64 "" \
  <<<'"browser_download_url": "https://example.invalid/releases/download/v1.0.0/stonerspots-backend-v1.0.0-linux-amd64.tar.gz"'
check "pick: an API error has nothing" pick release amd64 "" <<<'{"message": "Not Found"}'
# the names the release workflow gives the tarballs are the ones looked for
check "pick: dev-release.yml names tarballs stonerspots-backend-<tag>-linux-<arch>" \
  grep -qF 'name="stonerspots-backend-${TAG}-linux-${GOARCH}"' "$here/../.github/workflows/dev-release.yml"

# --- never back to older migrations -----------------------------------------

mig="$work/mig"
mkdir -p "$mig/many" "$mig/none" "$mig/octal"
for n in 0001 0002 0027; do touch "$mig/many/${n}_x.up.sql" "$mig/many/${n}_x.down.sql"; done
touch "$mig/many/0099_x.down.sql" "$mig/many/README.md" "$mig/octal/0009_x.up.sql" "$mig/octal/0010_y.up.sql"
check "migrations: newest up migration" test "$(newest_migration "$mig/many")" = 27
check "migrations: none is 0" test "$(newest_migration "$mig/none")" = 0
check "migrations: 0009 and 0010 are decimal" test "$(newest_migration "$mig/octal")" = 10
check "migrations: the real ones are counted" test "$(newest_migration "$here/../backend/migrations")" -gt 0

# --- units -----------------------------------------------------------------

units="$work/units"
mkdir -p "$units"
api_unit > "$units/stonerspots-backend.service"
updater_service_unit > "$units/stonerspots-update.service"
updater_path_unit > "$units/stonerspots-update.path"
has() { grep -qx -- "$1" "$units/$2"; }
for line in "StateDirectory=stonerspots" "StateDirectoryMode=0750" "UMask=0077" "MemoryMax=1G" \
  "Environment=GOMEMLIMIT=850MiB" "CapabilityBoundingSet=" "AmbientCapabilities=" \
  "ReadWritePaths=/var/lib/stonerspots-update/request" "SystemCallFilter=@system-service" \
  "RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX" "NoNewPrivileges=true" "ProtectSystem=strict" \
  "# stonerspots-units: ${UNITS_VERSION}"; do
  check "api unit: $line" has "$line" stonerspots-backend.service
done
check "api unit: no MemoryDenyWriteExecute (AVIF compiles wasm)" not grep -q '^MemoryDenyWriteExecute' "$units/stonerspots-backend.service"
check "updater unit: has a start timeout" has "TimeoutStartSec=20min" stonerspots-update.service
check "updater unit: writes only where updates write" \
  has "ReadWritePaths=-/opt/stonerspots -/etc/stonerspots -/var/lib/stonerspots-update -/etc/systemd/system" stonerspots-update.service
if command -v systemd-analyze >/dev/null && [ -d /run/systemd/system ]; then
  # the API binary and the user do not exist here; everything else must be clean
  raw=$(cd "$units" && systemd-analyze verify --man=no ./stonerspots-backend.service \
    ./stonerspots-update.service ./stonerspots-update.path 2>&1)
  if [ -n "${VERBOSE:-}" ]; then
    printf 'systemd-analyze verify said:\n%s\n' "$raw"
    for u in stonerspots-backend.service stonerspots-update.service; do
      (cd "$units" && systemd-analyze security --offline=true --no-pager "./$u" 2>&1 | tail -n 1)
    done
  fi
  # complaints about the machine's own units (e.g. on a CI image:
  # "CPUAccounting= has been removed" in xfs_scrub_all.service) are not ours
  out=$(printf '%s\n' "$raw" \
    | grep -vE "^/(usr/lib|lib|etc|run)/systemd/" \
    | grep -vE "/opt/stonerspots/(api|update-backend\.sh)|stonerspots-(backend|update)\.service: Command .* is not executable" || true)
  check "units: systemd-analyze verify is clean${out:+ (got: $out)}" test -z "$out"
else
  echo "skip  units: systemd-analyze verify (no systemd here)"
fi

# --- config hint ---------------------------------------------------------

conf() { printf '%s\n' "$1" > "$work/config.yaml"; addr_listens_everywhere "$work/config.yaml"; }
check "hint: addr \":8080\" listens everywhere" conf 'addr: ":8080"'
check "hint: addr 0.0.0.0" conf "addr: '0.0.0.0:8080'"
check "hint: addr [::]" conf 'addr: "[::]:8080"'
check "hint: no addr (default :8080)" conf 'public_base_url: "https://x"'
check "hint: addr 127.0.0.1 is fine" not conf 'addr: "127.0.0.1:8080"'
check "hint: addr [::1] is fine" not conf 'addr: "[::1]:8080"  # local'
check "hint: unquoted 127.0.0.1 is fine" not conf 'addr: 127.0.0.1:8080'

# --- a second backend (--instance) ----------------------------------------

check "instance: the default runner is the text as written" \
  eval 'diff <(update_runner) <(update_runner_text) >/dev/null'
inst() { (set_instance release && "$@"); } # in a subshell: globals stay
check "instance: own folders, units and user" inst eval '
  [ "$INSTALL_DIR" = /opt/stonerspots-release ] &&
  [ "$CONFIG_DIR" = /etc/stonerspots-release ] &&
  [ "$DATA_DIR" = /var/lib/stonerspots-release ] &&
  [ "$UPDATE_DIR" = /var/lib/stonerspots-release-update ] &&
  [ "$SERVICE" = stonerspots-release-backend ] &&
  [ "$UPDATER" = stonerspots-release-update ] &&
  [ "$SERVICE_USER" = stonerspots-release ] &&
  [ "$UNIT_FILE" = /etc/systemd/system/stonerspots-release-backend.service ] &&
  [ "$SIGNING_KEY" = /etc/stonerspots-release/release-signing.pub ]'
check "instance: runner uses its paths and user" inst eval '
  r=$(update_runner) &&
  grep -qx "req=/var/lib/stonerspots-release-update/request/channel" <<<"$r" &&
  grep -qx "api_user=stonerspots-release" <<<"$r" &&
  ! grep -qE "/opt/stonerspots/|stonerspots-update/" <<<"$r"'
check "instance: runner updates the same instance" inst eval '
  update_runner | grep -qF "exec /opt/stonerspots-release/install-backend.sh \"--\$channel\" --instance release)"'
check "instance: unit runs its own binary, config and user" inst eval '
  u=$(api_unit) &&
  grep -qx "ExecStart=/opt/stonerspots-release/api" <<<"$u" &&
  grep -qx "User=stonerspots-release" <<<"$u" &&
  grep -qx "Environment=CONFIG_FILE=/etc/stonerspots-release/config.yaml" <<<"$u" &&
  grep -qx "StateDirectory=stonerspots-release" <<<"$u"'
check "instance: path unit watches its own request" inst eval '
  updater_path_unit | grep -qx "PathExists=/var/lib/stonerspots-release-update/request/channel"'
for bad in "" "Release" "re-lease" "9lives" "../etc" "a b" "averyveryverylongname"; do
  check "instance: name '$bad' is refused" not eval "(set_instance '$bad') 2>/dev/null"
done

if [ "$failures" -gt 0 ]; then
  printf '\n%d failed\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
