#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/starter-kit/root/usr/lib/open-hotspot/activate-local-fas.sh"

sh -n "$script"
grep -F 'delete opennds.@opennds[0].fasremoteip' "$script" >/dev/null
grep -F 'delete opennds.@opennds[0].fasremotefqdn' "$script" >/dev/null
grep -F "gatewayfqdn='status.client'" "$script" >/dev/null
grep -F 'network.lan.device' "$script" >/dev/null
grep -F 'users_to_router' "$script" >/dev/null
grep -F 'assert_dynamic_local_fas' "$script" >/dev/null
grep -F 'hexdump -vn 32' "$script" >/dev/null
grep -F 'generated FAS key has an invalid length' "$script" >/dev/null
! grep -Eq "set opennds\.@opennds\[0\]\.fasremoteip='192\.168\." "$script"
! grep -Eq "set opennds\.@opennds\[0\]\.fasremotefqdn='192\.168\." "$script"

printf '%s\n' 'local-fas-dynamic-address-contract-ok'
