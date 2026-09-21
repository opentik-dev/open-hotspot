#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
v10="$root/starter-kit/root/usr/lib/open-hotspot/adapters/opennds-v10.3.1-r3.sh"
v11="$root/starter-kit/root/usr/lib/open-hotspot/adapters/opennds-v11.0.0.sh"

for script in "$v10" "$v11"; do
	[ -r "$script" ]
	sh -n "$script"
done
grep -F "OPEN_HOTSPOT_ADAPTER_ID='opennds-v10.3.1-r3'" "$v10" >/dev/null
grep -F "OPEN_HOTSPOT_ADAPTER_ID='opennds-v11.0.0'" "$v11" >/dev/null
grep -F 'unknown versions fail closed' \
	"$root/starter-kit/root/usr/lib/open-hotspot/opennds.sh" >/dev/null
! grep -Eq '192\.168\.' "$v10" "$v11"

printf '%s\n' 'versioned-adapter-contract-ok'
