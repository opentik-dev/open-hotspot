#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
guard="$root/starter-kit/root/usr/lib/open-hotspot/service-plane.sh"
preflight="$root/starter-kit/root/usr/lib/open-hotspot/preflight.sh"
activation="$root/starter-kit/root/usr/lib/open-hotspot/activate-local-fas.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock_uci="$tmp/uci"
cat > "$mock_uci" <<'EOF'
#!/bin/sh
case "$3" in
opennds.@opennds\[0\].gatewayinterface) printf '%s\n' "${MOCK_GATEWAY:-br-lan}" ;;
opennds.setup.gatewayinterface) printf '%s\n' "${MOCK_GATEWAY_SETUP:-}" ;;
network.lan.device) printf '%s\n' "${MOCK_MANAGEMENT:-br-lan}" ;;
network.lan.ifname) exit 1 ;;
open-hotspot.global.captive_plane_profile) printf '%s\n' "${MOCK_PROFILE:-protected}" ;;
open-hotspot.global.captive_plane_temporary_until) printf '%s\n' "${MOCK_UNTIL:-}" ;;
open-hotspot.global.captive_plane_temporary_ack) printf '%s\n' "${MOCK_ACK:-}" ;;
*) exit 1 ;;
esac
EOF
chmod +x "$mock_uci"

mock_date="$tmp/date"
cat > "$mock_date" <<'EOF'
#!/bin/sh
printf '%s\n' '2026-10-09'
EOF
chmod +x "$mock_date"

sh -n "$guard"
test -x "$guard"

if OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$guard" check >"$tmp/out" 2>"$tmp/err"; then
	echo 'expected protected profile on management bridge to fail' >&2
	exit 1
fi
grep -Fx 'service_plane_error=captive-gateway-is-management-service-interface' "$tmp/err" >/dev/null

MOCK_PROFILE=isolated MOCK_GATEWAY=br-hotspot MOCK_MANAGEMENT=br-lan \
	OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$guard" check >"$tmp/out" 2>"$tmp/err" || {
	cat "$tmp/out" >&2
	cat "$tmp/err" >&2
	exit 1
	}
grep -Fx 'captive_gateway_interface=br-hotspot' "$tmp/out" >/dev/null
grep -Fx 'service_plane=ok' "$tmp/out" >/dev/null

MOCK_PROFILE=isolated MOCK_GATEWAY=br-lan MOCK_GATEWAY_SETUP=br-hotspot MOCK_MANAGEMENT=br-lan \
	OPEN_HOTSPOT_UCI_BIN="$mock_uci" "$guard" check >"$tmp/out" 2>"$tmp/err" || {
	cat "$tmp/out" >&2
	cat "$tmp/err" >&2
	exit 1
	}
grep -Fx 'captive_gateway_interface=br-hotspot' "$tmp/out" >/dev/null

MOCK_PROFILE=temporary-shared-service MOCK_GATEWAY=br-lan MOCK_MANAGEMENT=br-lan \
	MOCK_UNTIL=2026-10-10 MOCK_ACK=I_ACCEPT_PREAUTH_SERVICE_EXPOSURE \
	OPEN_HOTSPOT_UCI_BIN="$mock_uci" OPEN_HOTSPOT_DATE_BIN="$mock_date" \
	"$guard" check >"$tmp/out" 2>"$tmp/err"
grep -Fx 'service_plane=ok' "$tmp/out" >/dev/null
grep -Fx 'service_plane_warning=temporary-profile-exposes-listed-router-services-before-captive-authentication' "$tmp/err" >/dev/null

if MOCK_PROFILE=temporary-shared-service MOCK_GATEWAY=br-lan MOCK_MANAGEMENT=br-lan \
	MOCK_UNTIL=2026-10-10 OPEN_HOTSPOT_UCI_BIN="$mock_uci" \
	OPEN_HOTSPOT_DATE_BIN="$mock_date" "$guard" check >"$tmp/out" 2>"$tmp/err"; then
	echo 'expected temporary profile without acknowledgement to fail' >&2
	exit 1
fi
grep -Fx 'service_plane_error=temporary-profile-requires-future-expiry-and-explicit-risk-acknowledgement' "$tmp/err" >/dev/null

grep -F 'OPEN_HOTSPOT_SERVICE_PLANE_GUARD' "$preflight" >/dev/null
grep -F 'service_plane_error=guard-unavailable' "$preflight" >/dev/null
grep -F 'SERVICE_PLANE_GUARD' "$activation" >/dev/null
grep -F '"$SERVICE_PLANE_GUARD" check' "$activation" >/dev/null

printf '%s\n' 'service-plane-guard-contract-ok'
