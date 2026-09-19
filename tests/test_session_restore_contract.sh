#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/starter-kit/root/usr/lib/open-hotspot/session-restore.sh"
setup="$root/starter-kit/luasrc/model/cbi/open-hotspot/setup.lua"
cycle="$root/starter-kit/root/usr/lib/open-hotspot/cycle.sh"

[ -x "$script" ]
sh -n "$script"
grep -F 'session_restore' "$script" >/dev/null
grep -F 'opennds_apply_session_policy' "$script" >/dev/null
grep -F 'db_usage_get' "$script" >/dev/null
grep -F 'quota_remaining' "$script" >/dev/null
grep -F 'session_restore_set' "$setup" >/dev/null
grep -F 'session-restore.sh restore' "$cycle" >/dev/null
! grep -Eq '192\.168\.|gatewayaddress|client_ip' "$script"

printf '%s\n' 'session-restore-contract-ok'
