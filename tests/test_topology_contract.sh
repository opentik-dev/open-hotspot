#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
preflight="$root/starter-kit/root/usr/lib/open-hotspot/preflight.sh"

sh -n "$preflight"
test -x "$preflight"
grep -F '_preflight_topology' "$preflight" >/dev/null
grep -F 'topology_error=lan-ip-equals-default-gateway' "$preflight" >/dev/null
grep -F 'topology_error=duplicate-local-ip:' "$preflight" >/dev/null
grep -F 'topology_error=lan-wan-overlap:' "$preflight" >/dev/null
grep -F "printf 'topology=ok" "$preflight" >/dev/null
grep -F 'preflight.sh) OPEN_HOTSPOT_PREFLIGHT_EXEC=1' "$preflight" >/dev/null
! grep -Eq '192\.168\.1\.1|192\.168\.70\.1' "$preflight"

printf '%s\n' 'topology-separation-contract-ok'
