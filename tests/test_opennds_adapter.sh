#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock="$tmp/ndsctl"
log="$tmp/args"
printf '%s\n' '#!/bin/sh' \
	'printf "%s\\n" "$*" >>"${OPEN_HOTSPOT_MOCK_LOG:?}"' \
	'case "$1" in status) printf "Version: 11.0.0\\n"; exit 0;; stop|start|restart) exit 0;; esac' >"$mock"
chmod +x "$mock"

init="$tmp/opennds-init"
printf '%s\n' '#!/bin/sh' 'case "$1" in stop|start|restart) exit 0;; esac' >"$init"
chmod +x "$init"

export OPEN_HOTSPOT_NDSCTL_BIN="$mock"
export OPEN_HOTSPOT_NDS_INIT="$init"
export OPEN_HOTSPOT_MOCK_LOG="$log"
export OPEN_HOTSPOT_ADAPTER_DIR="$root/starter-kit/root/usr/lib/open-hotspot/adapters"
. "$root/starter-kit/root/usr/lib/open-hotspot/opennds.sh"

opennds_validate_config
opennds_adapter_contract 10.3.1-r3
opennds_adapter_contract 11.0.0
if opennds_adapter_contract 12.0.0; then
	echo 'unknown openNDS adapter was accepted' >&2
	exit 1
fi
opennds_reload
opennds_apply_session_policy \
	AA:BB:CC:DD:EE:FF 61 128 1024 1025 1 'auth-key'
opennds_apply_session_policy \
	AA:BB:CC:DD:EE:FF 0 0 0 0 0
opennds_deauth AA:BB:CC:DD:EE:FF
sh "$root/starter-kit/root/usr/lib/open-hotspot/opennds.sh" deauth AA:BB:CC:DD:EE:FF

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
