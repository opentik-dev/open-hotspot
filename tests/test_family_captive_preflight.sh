#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/starter-kit/root/usr/lib/open-hotspot/family-captive-preflight.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock_uci="$tmp/uci"
cat > "$mock_uci" <<'EOF'
#!/bin/sh
case "$*" in
  "-q show opennds")
    printf '%s\n' 'opennds.setup=opennds'
    [ "${MOCK_SECOND_INSTANCE:-0}" = 1 ] && printf '%s\n' 'opennds.family=opennds'
    ;;
  "-q get open-hotspot.family_captive.state") printf '%s\n' "${MOCK_STATE:-disabled}" ;;
  "-q get open-hotspot.family_captive.device") printf '%s\n' "${MOCK_DEVICE:-}" ;;
  "-q get open-hotspot.family_captive.network") printf '%s\n' "${MOCK_NETWORK:-}" ;;
  "-q get open-hotspot.family_captive.enforcement_adapter") printf '%s\n' "${MOCK_ADAPTER:-}" ;;
  "-q get opennds.setup.gatewayinterface") printf '%s\n' "${MOCK_PRIMARY:-br-hotspot}" ;;
  "-q get opennds.@opennds[0].gatewayinterface") printf '%s\n' "${MOCK_PRIMARY:-br-hotspot}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$mock_uci"

sh -n "$script"
test -x "$script"

OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$script" check > "$tmp/disabled" 2> "$tmp/disabled.err"
grep -Fx 'family_captive_readiness=disabled' "$tmp/disabled" >/dev/null

if MOCK_STATE=staged MOCK_DEVICE=br-family MOCK_NETWORK=family MOCK_ADAPTER=multi-instance-v1 \
	OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$script" check > "$tmp/single" 2> "$tmp/single.err"; then
	echo 'expected a single openNDS instance to block Family Captive' >&2
	exit 1
fi
grep -Fx 'family_captive_error=separate-opennds-instance-not-configured' "$tmp/single.err" >/dev/null
grep -Fx 'family_captive_action=do-not-create-or-enable-family-ssid-yet' "$tmp/single.err" >/dev/null

if MOCK_STATE=enabled MOCK_DEVICE=br-hotspot MOCK_NETWORK=family MOCK_ADAPTER=multi-instance-v1 \
	OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$script" check > "$tmp/shared" 2> "$tmp/shared.err"; then
	echo 'expected Family Captive to reject the primary captive bridge' >&2
	exit 1
fi
grep -Fx 'family_captive_error=device-must-not-share-primary-captive-bridge' "$tmp/shared.err" >/dev/null

if MOCK_STATE=enabled MOCK_DEVICE=br-family MOCK_NETWORK=family MOCK_ADAPTER=multi-instance-v1 MOCK_SECOND_INSTANCE=1 \
	OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$script" check > "$tmp/contract" 2> "$tmp/contract.err"; then
	echo 'expected unimplemented multi-instance runtime contract to block activation' >&2
	exit 1
fi
grep -Fx 'family_captive_error=multi-instance-runtime-contract-not-yet-implemented' "$tmp/contract.err" >/dev/null

printf '%s\n' 'family-captive-preflight-contract-ok'
