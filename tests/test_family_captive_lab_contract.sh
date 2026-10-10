#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
validator="$root/tools/family-captive-lab-validate.sh"
fixture="$root/tests/fixtures/family-captive-lab.plan"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sh -n "$validator"
"$validator" "$fixture" > "$tmp/ok"
grep -Fx 'family_captive_lab_contract=ok' "$tmp/ok" >/dev/null

sed 's|family.device=br-family|family.device=br-hotspot|' "$fixture" > "$tmp/device-collision"
if "$validator" "$tmp/device-collision" > /dev/null 2> "$tmp/device-collision.err"; then
	echo 'expected bridge collision to fail' >&2
	exit 1
fi
grep -Fx 'family-captive-lab: device-collision' "$tmp/device-collision.err" >/dev/null

sed 's|family.ndsctlsocket=opennds-family/ndsctl.sock|family.ndsctlsocket=opennds-guest/ndsctl.sock|' "$fixture" > "$tmp/socket-collision"
if "$validator" "$tmp/socket-collision" > /dev/null 2> "$tmp/socket-collision.err"; then
	echo 'expected control socket collision to fail' >&2
	exit 1
fi
grep -Fx 'family-captive-lab: control-socket-collision' "$tmp/socket-collision.err" >/dev/null

sed 's|family.fas_plane=family|family.fas_plane=guest|' "$fixture" > "$tmp/fas-collision"
if "$validator" "$tmp/fas-collision" > /dev/null 2> "$tmp/fas-collision.err"; then
	echo 'expected FAS plane collision to fail' >&2
	exit 1
fi
grep -Fx 'family-captive-lab: fas-plane-collision' "$tmp/fas-collision.err" >/dev/null

sed 's|family.nft_chain=opennds_family_auth|family.nft_chain=opennds_guest_auth|' "$fixture" > "$tmp/chain-collision"
if "$validator" "$tmp/chain-collision" > /dev/null 2> "$tmp/chain-collision.err"; then
	echo 'expected nft chain collision to fail' >&2
	exit 1
fi
grep -Fx 'family-captive-lab: nft-chain-collision' "$tmp/chain-collision.err" >/dev/null

sed 's|family.procd_service=opennds-family|family.procd_service=opennds-guest|' "$fixture" > "$tmp/service-collision"
if "$validator" "$tmp/service-collision" > /dev/null 2> "$tmp/service-collision.err"; then
	echo 'expected procd service collision to fail' >&2
	exit 1
fi
grep -Fx 'family-captive-lab: procd-service-collision' "$tmp/service-collision.err" >/dev/null

printf '%s\n' 'family-captive-lab-contract-ok'
