#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

plan=$(OPEN_HOTSPOT_PACKAGE_PLAN_EXEC=1 \
	sh "$root/starter-kit/root/usr/lib/open-hotspot/package-plan.sh")
[ "$plan" = "opennds
sqlite3-cli
php8-cgi
php8-mod-pdo-sqlite
luci-base
luci-compat" ]
! printf '%s\n' "$plan" | grep -Fx 'dnsmasq-full' >/dev/null

export MOCK_UCI_STATE="$tmp/uci.state"
export MOCK_DB_MARKER="$tmp/db.initialized"
export MOCK_PREFLIGHT_MARKER="$tmp/preflight.called"
export OPEN_HOTSPOT_UCI_BIN="$root/tests/fixtures/mock-uci.sh"
export OPEN_HOTSPOT_DB_HELPER="$root/tests/fixtures/setup-db.sh"
export OPEN_HOTSPOT_PREFLIGHT="$root/tests/fixtures/setup-preflight.sh"
chmod +x "$OPEN_HOTSPOT_UCI_BIN"
"$OPEN_HOTSPOT_UCI_BIN" set open-hotspot.global.fas_mode=local-level1
"$OPEN_HOTSPOT_UCI_BIN" set open-hotspot.global.fas_port=2080
"$OPEN_HOTSPOT_UCI_BIN" set open-hotspot.global.fas_path=/nds/fas.php
"$OPEN_HOTSPOT_UCI_BIN" set open-hotspot.global.local_fas_enabled=0

sh "$root/starter-kit/root/usr/lib/open-hotspot/setup.sh" base
[ -f "$MOCK_DB_MARKER" ]
[ -f "$MOCK_PREFLIGHT_MARKER" ]
grep -Fx 'setup_state=BASE_READY' "$MOCK_UCI_STATE" >/dev/null
grep -Fx 'setup_last_error=' "$MOCK_UCI_STATE" >/dev/null

status=$(sh "$root/starter-kit/root/usr/lib/open-hotspot/setup.sh" status)
printf '%s\n' "$status" | grep -Fx 'state=BASE_READY' >/dev/null
printf '%s\n' "$status" | grep -Fx 'fas_mode=local-level1' >/dev/null
printf '%s\n' "$status" | grep -Fx 'fas_port=2080' >/dev/null
printf '%s\n' "$status" | grep -Fx 'local_fas_enabled=0' >/dev/null

before=$(cat "$MOCK_UCI_STATE")
sh "$root/starter-kit/root/usr/lib/open-hotspot/setup.sh" base
[ "$(cat "$MOCK_UCI_STATE")" = "$before" ]
