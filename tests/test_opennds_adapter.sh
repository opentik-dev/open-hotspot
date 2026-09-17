#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock="$tmp/ndsctl"
log="$tmp/args"
printf '%s\n' '#!/bin/sh' \
	'printf "%s\\n" "$*" >>"${OPEN_HOTSPOT_MOCK_LOG:?}"' \
	'case "$1" in status) exit 0;; esac' >"$mock"
chmod +x "$mock"

init="$tmp/opennds-init"
printf '%s\n' '#!/bin/sh' 'test "$1" = restart' >"$init"
chmod +x "$init"

export OPEN_HOTSPOT_NDSCTL_BIN="$mock"
export OPEN_HOTSPOT_NDS_INIT="$init"
export OPEN_HOTSPOT_MOCK_LOG="$log"
. "$root/starter-kit/root/usr/lib/open-hotspot/opennds.sh"

opennds_validate_config
opennds_reload
opennds_apply_session_policy \
	AA:BB:CC:DD:EE:FF 61 128 1024 1025 1 'auth-key'
opennds_apply_session_policy \
	AA:BB:CC:DD:EE:FF 0 0 0 0 0
opennds_deauth AA:BB:CC:DD:EE:FF

grep -F 'auth AA:BB:CC:DD:EE:FF 2 128 1024 2 1 auth-key' "$log" >/dev/null
grep -F 'auth AA:BB:CC:DD:EE:FF 0 0 0 0 0 ' "$log" >/dev/null
grep -F 'deauth AA:BB:CC:DD:EE:FF' "$log" >/dev/null

if opennds_deauth 'not-a-mac'; then
	echo 'invalid MAC was accepted' >&2
	exit 1
fi
if opennds_apply_session_policy AA:BB:CC:DD:EE:FF 1 bad 1 0 0 >/dev/null 2>&1; then
	echo 'invalid rate was accepted' >&2
	exit 1
fi
