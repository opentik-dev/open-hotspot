#!/bin/sh
# preflight.sh — read-only compatibility checks for a clean router.
#
# It does not install packages, restart services, alter UCI, or replace
# dnsmasq. A failed check is a setup blocker, not a reason to guess.

OPEN_HOTSPOT_PHP_BIN="${OPEN_HOTSPOT_PHP_BIN:-php8-cgi}"
OPEN_HOTSPOT_NDS_BIN="${OPEN_HOTSPOT_NDS_BIN:-opennds}"
OPEN_HOTSPOT_NDSCTL_BIN="${OPEN_HOTSPOT_NDSCTL_BIN:-ndsctl}"

_preflight_have() {
	command -v "$1" >/dev/null 2>&1
}

_preflight_check_php() {
	_preflight_have "$OPEN_HOTSPOT_PHP_BIN" || return 1
	REDIRECT_STATUS=1 "$OPEN_HOTSPOT_PHP_BIN" -m 2>/dev/null \
		| grep -Fx 'PDO' >/dev/null || return 1
	REDIRECT_STATUS=1 "$OPEN_HOTSPOT_PHP_BIN" -m 2>/dev/null \
		| grep -Fx 'pdo_sqlite' >/dev/null || return 1
	REDIRECT_STATUS=1 "$OPEN_HOTSPOT_PHP_BIN" -m 2>/dev/null \
		| grep -Fx 'hash' >/dev/null || return 1
}

_preflight_topology() {
	gateway_if=$($OPEN_HOTSPOT_UCI_BIN -q get opennds.@opennds[0].gatewayinterface 2>/dev/null || true)
	[ -n "$gateway_if" ] || gateway_if='br-lan'
	lan_ip=$(ip -4 addr show dev "$gateway_if" 2>/dev/null |
		awk '$1 == "inet" {sub(/\/.*/, "", $2); print $2; exit}')
	default_line=$(ip -4 route show default 2>/dev/null | sed -n '1p')
	default_gateway=$(printf '%s\n' "$default_line" | awk '{for (i=1; i<=NF; i++) if ($i == "via") {print $(i+1); exit}}')
	wan_if=$(printf '%s\n' "$default_line" | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')
	lan_network=$(ip -4 route show dev "$gateway_if" scope link 2>/dev/null |
		awk 'NR == 1 {print $1; exit}')
	wan_network=''
	[ -n "$wan_if" ] && wan_network=$(ip -4 route show dev "$wan_if" scope link 2>/dev/null |
		awk 'NR == 1 {print $1; exit}')

	printf 'lan_interface=%s\n' "$gateway_if"
	printf 'lan_ip=%s\n' "$lan_ip"
	printf 'wan_interface=%s\n' "$wan_if"
	printf 'wan_network=%s\n' "$wan_network"

	[ -n "$lan_ip" ] || {
		echo 'topology_error=lan-ip-unavailable' >&2
		return 1
	}
	[ "$lan_ip" != "$default_gateway" ] || {
		echo 'topology_error=lan-ip-equals-default-gateway' >&2
		return 1
	}
	duplicate_ip=$(ip -4 addr show 2>/dev/null |
		awk '$1 == "inet" {sub(/\/.*/, "", $2); print $2}' |
		sort | uniq -d | sed -n '1p')
	[ -z "$duplicate_ip" ] || {
		echo "topology_error=duplicate-local-ip:$duplicate_ip" >&2
		return 1
	}
	if [ -n "$lan_network" ] && [ -n "$wan_network" ] &&
		[ "$lan_network" = "$wan_network" ]; then
		echo "topology_error=lan-wan-overlap:$lan_network" >&2
		return 1
	fi
	printf 'topology=ok\n'
}

open_hotspot_preflight() {
	failed=''
	OPEN_HOTSPOT_UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
	for command_name in "$OPEN_HOTSPOT_UCI_BIN" ip sqlite3 uhttpd ubus rpcd "$OPEN_HOTSPOT_NDS_BIN" "$OPEN_HOTSPOT_NDSCTL_BIN" flock; do
		_preflight_have "$command_name" || failed="$failed $command_name"
	done
	[ -r /usr/share/libubox/jshn.sh ] || failed="$failed jshn"
	_preflight_check_php || failed="$failed php-runtime"
	[ -n "$failed" ] && {
		echo "missing:$failed" >&2
		return 1
	}

	version=$($OPEN_HOTSPOT_NDS_BIN -v 2>&1 | sed -n '1p') || return 1
	[ -n "$version" ] || return 1
	_preflight_topology || failed="$failed topology"
	[ -z "$failed" ] || {
		printf 'preflight_error=%s\n' "$failed" >&2
		return 1
	}
	printf 'opennds_version=%s\n' "$version"
	printf 'dnsmasq_full=not-required-by-core-plan\n'
	printf 'fas_mode=local-level1\n'
	printf 'fas_port=2080\n'
}

case "${0##*/}" in
	preflight.sh) OPEN_HOTSPOT_PREFLIGHT_EXEC=1 ;;
esac

if [ "${OPEN_HOTSPOT_PREFLIGHT_EXEC:-0}" = 1 ]; then
	open_hotspot_preflight
fi
