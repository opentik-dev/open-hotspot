#!/bin/sh
# Manage access from a dedicated Open-HotSpot client network to router admin
# services. This is intentionally separate from openNDS users_to_router:
# openNDS always preserves essential router ports such as SSH and LuCI HTTPS.

UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
FIREWALL_INIT="${OPEN_HOTSPOT_FIREWALL_INIT:-/etc/init.d/firewall}"
ZONE='open_hotspot_clients'
RULE='open_hotspot_deny_router_admin'
WAN_FORWARDING='open_hotspot_clients_to_wan'

die() {
	echo "open-hotspot: $1" >&2
	return 1
}

valid_network() {
	case "$1" in
		''|*[!A-Za-z0-9_.-]*) return 1 ;;
		*) return 0 ;;
	esac
}

valid_mode() {
	case "$1" in deny|allow) return 0 ;; *) return 1 ;; esac
}

network_device() {
	network="$1"
	device=$("$UCI_BIN" -q get "network.$network.device" 2>/dev/null || true)
	[ -n "$device" ] || device=$("$UCI_BIN" -q get "network.$network.ifname" 2>/dev/null || true)
	[ -n "$device" ] || return 1
	printf '%s\n' "$device"
}

gateway_device() {
	device=$("$UCI_BIN" -q get opennds.@opennds[0].gatewayinterface 2>/dev/null || true)
	[ -n "$device" ] || device=$("$UCI_BIN" -q get network.lan.device 2>/dev/null || true)
	[ -n "$device" ] || device=$("$UCI_BIN" -q get network.lan.ifname 2>/dev/null || true)
	[ -n "$device" ] || return 1
	printf '%s\n' "$device"
}

network_is_already_zoned() {
	network="$1"
	zone_section="$2"
	"$UCI_BIN" -q show firewall 2>/dev/null |
		grep -F "network='$network'" |
		grep -v -F "firewall.$zone_section" >/dev/null 2>&1
}

firewall_zone_for_network() {
	network="$1"
	"$UCI_BIN" -q show firewall 2>/dev/null |
		awk -F= -v wanted="$network" '
			$1 ~ /^firewall\.[^.]+\.network$/ {
				value=$2
				gsub(/['\''"]/, "", value)
				n=split(value, networks, /[[:space:]]+/)
				for (i = 1; i <= n; i++) if (networks[i] == wanted) {
					split($1, key, "."); print key[2]; exit
				}
			}'
}

wan_zone() {
	"$UCI_BIN" -q get network.wan >/dev/null || return 1
	zone=$(firewall_zone_for_network wan)
	[ -n "$zone" ] || return 1
	printf '%s\n' "$zone"
}

apply_policy() {
	mode="$1"
	network="$2"
	valid_mode "$mode" || die 'router access mode must be deny or allow'
	valid_network "$network" || die 'client network name is invalid'
	"$UCI_BIN" -q get "network.$network" >/dev/null || die 'client network does not exist'
	client_device=$(network_device "$network") || die 'client network device is not discoverable'
	gateway_device=$(gateway_device) || die 'gateway interface is not discoverable'
	if [ "$client_device" = "$gateway_device" ]; then
		die 'client network must be isolated from the gateway/management interface'
		return 1
	fi
	if network_is_already_zoned "$network" "$ZONE"; then
		die 'client network already belongs to another firewall zone'
		return 1
	fi
	wan_zone=$(wan_zone) || {
		die 'WAN firewall zone is not discoverable; no IoT policy was applied'
		return 1
	}

	# The rule is port-based and therefore independent of the router's current
	# LAN/WAN address. Port 2050/2080 remain available for the captive flow.
	"$UCI_BIN" set "firewall.$ZONE=zone" || return 1
	"$UCI_BIN" delete "firewall.$ZONE.network" 2>/dev/null || true
	"$UCI_BIN" add_list "firewall.$ZONE.network=$network" || return 1
	"$UCI_BIN" set "firewall.$ZONE.input=ACCEPT" || return 1
	"$UCI_BIN" set "firewall.$ZONE.output=ACCEPT" || return 1
	"$UCI_BIN" set "firewall.$ZONE.forward=REJECT" || return 1
	"$UCI_BIN" set "firewall.$ZONE.name=Open-HotSpot clients" || return 1
	# IoT devices have Internet egress only. No forwarding to the management/LAN
	# zone is created, and no unverified openNDS trusted-MAC bypass is used.
	"$UCI_BIN" set "firewall.$WAN_FORWARDING=forwarding" || return 1
	"$UCI_BIN" set "firewall.$WAN_FORWARDING.src=$ZONE" || return 1
	"$UCI_BIN" set "firewall.$WAN_FORWARDING.dest=$wan_zone" || return 1

	"$UCI_BIN" set "open-hotspot.global.client_network=$network" || return 1
	"$UCI_BIN" set "open-hotspot.global.client_router_access=$mode" || return 1
	if [ "$mode" = deny ]; then
		"$UCI_BIN" set "firewall.$RULE=rule" || return 1
		"$UCI_BIN" set "firewall.$RULE.name=Open-HotSpot deny router admin" || return 1
		"$UCI_BIN" set "firewall.$RULE.src=$ZONE" || return 1
		"$UCI_BIN" set "firewall.$RULE.proto=tcp" || return 1
		"$UCI_BIN" set "firewall.$RULE.dest_port=22 80 443" || return 1
		"$UCI_BIN" set "firewall.$RULE.target=DROP" || return 1
	else
		"$UCI_BIN" delete "firewall.$RULE" 2>/dev/null || true
	fi
	"$UCI_BIN" commit firewall || return 1
	"$UCI_BIN" commit open-hotspot || return 1
	"$FIREWALL_INIT" reload >/dev/null 2>&1 || return 1
	printf 'client_network=%s\nclient_router_access=%s\niot_wan_zone=%s\n' "$network" "$mode" "$wan_zone"
}

status() {
	printf 'client_network=%s\n' "$("$UCI_BIN" -q get open-hotspot.global.client_network 2>/dev/null || true)"
	printf 'client_router_access=%s\n' "$("$UCI_BIN" -q get open-hotspot.global.client_router_access 2>/dev/null || true)"
}

case "${1:-}" in
	apply) shift; [ "$#" -eq 2 ] || die 'usage: router-access.sh apply {deny|allow} <network>'; apply_policy "$@" ;;
	status) status ;;
	*) echo 'usage: router-access.sh {apply|status}' >&2; exit 2 ;;
esac
