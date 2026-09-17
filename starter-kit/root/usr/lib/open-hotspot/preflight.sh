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

open_hotspot_preflight() {
	failed=''
	for command_name in uci sqlite3 uhttpd ubus rpcd "$OPEN_HOTSPOT_NDS_BIN" "$OPEN_HOTSPOT_NDSCTL_BIN" flock; do
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
	printf 'opennds_version=%s\n' "$version"
	printf 'dnsmasq_full=not-required-by-core-plan\n'
	printf 'fas_mode=local-level1\n'
	printf 'fas_port=2080\n'
}

if [ "${OPEN_HOTSPOT_PREFLIGHT_EXEC:-0}" = 1 ]; then
	open_hotspot_preflight
fi
