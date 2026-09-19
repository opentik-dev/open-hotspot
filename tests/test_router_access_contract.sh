#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/starter-kit/root/usr/lib/open-hotspot/router-access.sh"

sh -n "$script"
test -x "$script"
grep -F 'client_router_access' "$script" >/dev/null
grep -F 'client_network' "$script" >/dev/null
grep -F 'dest_port=22 80 443' "$script" >/dev/null
grep -F 'gateway/management interface' "$script" >/dev/null
grep -F 'if [ "$client_device" = "$gateway_device" ]; then' "$script" >/dev/null
grep -F 'if network_is_already_zoned "$network" "$ZONE"; then' "$script" >/dev/null
! grep -Eq '192\.168\.[0-9]+\.[0-9]+' "$script"

printf '%s\n' 'router-access-contract-ok'
