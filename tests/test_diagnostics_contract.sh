#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/starter-kit/root/usr/lib/open-hotspot/diagnose.sh"

sh -n "$script"
grep -F 'OPEN_HOTSPOT_DIAGNOSTIC_V1' "$script" >/dev/null
grep -F 'custombinauthpath=$(uci -q get opennds.@opennds[0].custombinauth' "$script" >/dev/null
grep -F 'database_counts=' "$script" >/dev/null
grep -F 'opennds-authenticated-without-manager-session' "$script" >/dev/null
grep -F 'fas=http-local-listener-responds' "$script" >/dev/null
grep -F 'fasremoteip=' "$script" >/dev/null
! grep -Eq '192\.168\.[0-9]+\.[0-9]+' "$script"
! grep -Eq '(^|[^A-Za-z])(faskey|fas_key|PIN|pin)([^A-Za-z]|$)' "$script"

printf '%s\n' 'diagnostics-contract-ok'
