#!/bin/sh
# service-plane.sh — guard the boundary between captive and router-service planes.
#
# This helper never changes firewall, wireless, openNDS, or service settings.
# It exists so an activation cannot accidentally make the management/service
# bridge captive again.  The only bypass is an explicitly time-bounded,
# documented temporary profile; it is intentionally not the default.

UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
DATE_BIN="${OPEN_HOTSPOT_DATE_BIN:-date}"

die() {
	echo "open-hotspot: $1" >&2
	return 1
}

uci_get() {
	"$UCI_BIN" -q get "$1" 2>/dev/null || true
}

gateway_device() {
	device=$(uci_get opennds.@opennds[0].gatewayinterface)
	[ -n "$device" ] || device=$(uci_get network.lan.device)
	[ -n "$device" ] || device=$(uci_get network.lan.ifname)
	[ -n "$device" ] || return 1
	printf '%s\n' "$device"
}

management_device() {
	device=$(uci_get network.lan.device)
	[ -n "$device" ] || device=$(uci_get network.lan.ifname)
	[ -n "$device" ] || return 1
	printf '%s\n' "$device"
}

temporary_profile_valid() {
	until=$(uci_get open-hotspot.global.captive_plane_temporary_until)
	ack=$(uci_get open-hotspot.global.captive_plane_temporary_ack)
	today=$($DATE_BIN -u +%F 2>/dev/null || true)
	case "$until" in
		????-??-??) ;;
		*) return 1 ;;
	esac
	[ "$ack" = 'I_ACCEPT_PREAUTH_SERVICE_EXPOSURE' ] || return 1
	[ -n "$today" ] && [ "$today" \< "$until" ]
}

check() {
	profile=$(uci_get open-hotspot.global.captive_plane_profile)
	[ -n "$profile" ] || profile='protected'
	gateway=$(gateway_device) || die 'captive gateway interface is not discoverable'
	management=$(management_device) || die 'management/service interface is not discoverable'

	printf 'captive_plane_profile=%s\n' "$profile"
	printf 'captive_gateway_interface=%s\n' "$gateway"
	printf 'management_service_interface=%s\n' "$management"

	case "$profile" in
		protected)
			if [ "$gateway" = "$management" ]; then
				echo 'service_plane_error=captive-gateway-is-management-service-interface' >&2
				echo 'service_plane_action=create-a-dedicated-captive-bridge-before-activation' >&2
				return 1
			fi
			;;
		isolated)
			if [ "$gateway" = "$management" ]; then
				echo 'service_plane_error=isolated-profile-uses-management-service-interface' >&2
				return 1
			fi
			;;
		temporary-shared-service)
			if [ "$gateway" != "$management" ]; then
				echo 'service_plane_error=temporary-profile-is-only-valid-on-management-service-interface' >&2
				return 1
			fi
			temporary_profile_valid || {
				echo 'service_plane_error=temporary-profile-requires-future-expiry-and-explicit-risk-acknowledgement' >&2
				return 1
			}
			echo 'service_plane_warning=temporary-profile-exposes-listed-router-services-before-captive-authentication' >&2
			;;
		*)
			echo 'service_plane_error=unknown-captive-plane-profile' >&2
			return 1
			;;
	esac

	printf 'service_plane=ok\n'
}

status() {
	printf 'captive_plane_profile=%s\n' "$(uci_get open-hotspot.global.captive_plane_profile)"
	printf 'captive_plane_temporary_until=%s\n' "$(uci_get open-hotspot.global.captive_plane_temporary_until)"
	printf 'captive_gateway_interface=%s\n' "$(gateway_device 2>/dev/null || true)"
	printf 'management_service_interface=%s\n' "$(management_device 2>/dev/null || true)"
}

case "${1:-}" in
	check) check ;;
	status) status ;;
	*) echo 'usage: service-plane.sh {check|status}' >&2; exit 2 ;;
esac
