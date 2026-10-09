#!/bin/sh
# Read-only topology diagnostics. It never changes routes, UCI, or firewall.

IP_BIN="${OPEN_HOTSPOT_IP_BIN:-ip}"
UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
NDSCTL_BIN="${OPEN_HOTSPOT_NDSCTL_BIN:-ndsctl}"

usage() { echo 'usage: network-audit.sh {summary|route <IPv4>}' >&2; }

valid_ipv4() {
	printf '%s\n' "$1" | awk -F. '
		NF == 4 { for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || $i > 255) exit 1; exit 0 }
		{ exit 1 }'
}

default_interface() {
	"$IP_BIN" -4 route show default 2>/dev/null |
		awk 'NR == 1 { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

opennds_client_count() {
	"$NDSCTL_BIN" status 2>/dev/null |
		awk -F: '/^Current clients:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }'
}

present() { if "$@" >/dev/null 2>&1; then echo present; else echo absent; fi; }

summary() {
	default_dev=$(default_interface)
	[ -n "$default_dev" ] && default_state=present || default_state=absent
	printf 'default_route=%s\ndefault_interface=%s\n' "$default_state" "$default_dev"
	printf 'tailscale_binary=%s\n' "$(present command -v tailscale)"
	printf 'tailscale_interface=%s\n' "$(present "$IP_BIN" link show dev tailscale0)"
	printf 'opennds_clients=%s\n' "$(opennds_client_count || true)"
	printf 'iot_network=%s\n' "$("$UCI_BIN" -q get open-hotspot.global.client_network 2>/dev/null || true)"
	printf 'iot_wan_forward_src=%s\n' "$("$UCI_BIN" -q get firewall.open_hotspot_clients_to_wan.src 2>/dev/null || true)"
	printf 'iot_wan_forward_dest=%s\n' "$("$UCI_BIN" -q get firewall.open_hotspot_clients_to_wan.dest 2>/dev/null || true)"
}

route_to() {
	destination="$1"
	valid_ipv4 "$destination" || { echo 'network-audit: route destination must be IPv4' >&2; return 2; }
	route=$("$IP_BIN" -4 route get "$destination" 2>/dev/null) || { echo 'route_lookup=unreachable'; return 1; }
	device=$(printf '%s\n' "$route" | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')
	printf 'route_lookup=reachable\nroute_device=%s\n' "$device"
}

case "${1:-}" in
	summary) [ "$#" -eq 1 ] || { usage; exit 2; }; summary ;;
	route) [ "$#" -eq 2 ] || { usage; exit 2; }; route_to "$2" ;;
	*) usage; exit 2 ;;
esac
