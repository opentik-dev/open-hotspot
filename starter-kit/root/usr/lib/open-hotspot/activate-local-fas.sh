#!/bin/sh
# Explicit local-FAS activation with a reversible configuration checkpoint.
#
# The base package never changes openNDS. This command is the deliberate
# second-stage operation after the administrator has verified the local FAS.

UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
UHTTPD_INIT="${OPEN_HOTSPOT_UHTTPD_INIT:-/etc/init.d/uhttpd}"
OPENNDS_INIT="${OPEN_HOTSPOT_OPENNDS_INIT:-/etc/init.d/opennds}"
BACKUP_ROOT="${OPEN_HOTSPOT_ACTIVATION_BACKUPS:-/etc/open-hotspot/activation-backups}"

die() {
	echo "open-hotspot: $1" >&2
	return 1
}

require_file() {
	[ -r "$1" ] || die "missing required file: $1"
}

backup_current() {
	stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
	dir="$BACKUP_ROOT/$stamp"
	mkdir -p "$dir" || return 1
	cp /etc/config/opennds "$dir/opennds" || return 1
	cp /etc/config/uhttpd "$dir/uhttpd" || return 1
	cp /usr/lib/opennds/custombinauth.sh "$dir/custombinauth.sh" || return 1
	printf '%s\n' "$dir" > "$BACKUP_ROOT/latest" || return 1
	printf '%s\n' "$dir"
}

restore_backup() {
	dir="$1"
	require_file "$dir/opennds" || return 1
	require_file "$dir/uhttpd" || return 1
	require_file "$dir/custombinauth.sh" || return 1
	cp "$dir/opennds" /etc/config/opennds || return 1
	cp "$dir/uhttpd" /etc/config/uhttpd || return 1
	cp "$dir/custombinauth.sh" /usr/lib/opennds/custombinauth.sh || return 1
	chmod 0755 /usr/lib/opennds/custombinauth.sh || return 1
}

reload_services() {
	"$UHTTPD_INIT" restart >/dev/null 2>&1 || return 1
	. /usr/lib/open-hotspot/opennds.sh
	opennds_reload
}

fas_probe() {
	probe=/tmp/open-hotspot-fas-probe.$$
	# Keep the probe independent of optional BusyBox applets: this is the
	# base64 encoding of a fixed, non-secret level-1 request.
	payload='aGlkPXByb2JlLCBjbGllbnRtYWM9QUE6QkI6Q0M6REQ6RUU6RkYsIGdhdGV3YXlhZGRyZXNzPTEyNy4wLjAuMSwgYXV0aGRpcj1vcGVubmRzX2F1dGgsIG9yaWdpbnVybD1odHRwOi8vMTI3LjAuMC4xLw=='
	rm -f "$probe"
	wget -qO "$probe" "http://127.0.0.1:2080/nds/fas.php?fas=$payload" || true
	grep -F 'Open-HotSpot' "$probe" >/dev/null 2>&1
	rc=$?
	rm -f "$probe"
	return "$rc"
}

activate() {
	[ "$(id -u)" = 0 ] || die 'must run as root'
	require_file /etc/config/opennds || return 1
	require_file /etc/config/uhttpd || return 1
	require_file /usr/lib/open-hotspot/custombinauth.sh || return 1
	require_file /usr/lib/open-hotspot/opennds.sh || return 1
	"$UCI_BIN" -q get opennds.@opennds[0] >/dev/null || die 'openNDS UCI section missing'
	"$UCI_BIN" -q get opennds.@opennds[0].faskey >/dev/null || die 'FAS key is not configured'

	dir=$(backup_current) || return 1

	# uhttpd's documented UCI instance model provides a separate local HTTP
	# listener, keeping port 80 available to the captive portal.
	"$UCI_BIN" set uhttpd.open_hotspot_fas='uhttpd' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.enabled='1' || return 1
	"$UCI_BIN" delete uhttpd.open_hotspot_fas.listen_https 2>/dev/null || true
	"$UCI_BIN" delete uhttpd.open_hotspot_fas.listen_http 2>/dev/null || true
	"$UCI_BIN" add_list uhttpd.open_hotspot_fas.listen_http='0.0.0.0:2080' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.home='/www' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.interpreter='.php=/usr/bin/php-cgi' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.no_dirlists='1' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.no_symlinks='1' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.rfc1918_filter='0' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.max_requests='3' || return 1
	"$UCI_BIN" set uhttpd.open_hotspot_fas.max_connections='32' || return 1
	"$UCI_BIN" commit uhttpd || return 1
	"$UHTTPD_INIT" restart >/dev/null 2>&1 || return 1
	fas_probe || {
		restore_backup "$dir"
		"$UHTTPD_INIT" restart >/dev/null 2>&1 || true
		return 1
	}

	# Only replace the active BinAuth after the local FAS listener is healthy.
	cp /usr/lib/open-hotspot/custombinauth.sh /usr/lib/opennds/custombinauth.sh || return 1
	chmod 0755 /usr/lib/opennds/custombinauth.sh || return 1
	"$UCI_BIN" delete opennds.@opennds[0].fasremoteip 2>/dev/null || true
	"$UCI_BIN" delete opennds.@opennds[0].fasremotefqdn 2>/dev/null || true
	"$UCI_BIN" set opennds.@opennds[0].fasport='2080' || return 1
	"$UCI_BIN" set opennds.@opennds[0].faspath='/nds/fas.php' || return 1
	"$UCI_BIN" set opennds.@opennds[0].fas_secure_enabled='1' || return 1
	# Use openNDS's documented local client-status hostname so clients can
	# reach the portal without being shown the router's numeric address.
	"$UCI_BIN" set opennds.@opennds[0].gatewayfqdn='status.client' || return 1
	# Local FAS is an optional router service; allow the captive client to
	# reach only its documented listener in addition to existing allowances.
	"$UCI_BIN" add_list opennds.@opennds[0].users_to_router='allow tcp port 2080' || return 1
	"$UCI_BIN" commit opennds || return 1
	. /usr/lib/open-hotspot/opennds.sh
	if opennds_reload; then
		"$UCI_BIN" set open-hotspot.global.local_fas_enabled='1' || return 1
		"$UCI_BIN" commit open-hotspot || return 1
		printf 'local_fas_enabled=1\nbackup=%s\n' "$dir"
		return 0
	fi

	# Fail closed: restore both services and the previous BinAuth.
	restore_backup "$dir" || true
	"$UHTTPD_INIT" restart >/dev/null 2>&1 || true
	. /usr/lib/open-hotspot/opennds.sh
	opennds_reload || "$OPENNDS_INIT" restart >/dev/null 2>&1 || true
	return 1
}

rollback() {
	[ -r "$BACKUP_ROOT/latest" ] || die 'no activation checkpoint found'
	dir=$(cat "$BACKUP_ROOT/latest")
	restore_backup "$dir" || return 1
	"$UHTTPD_INIT" restart >/dev/null 2>&1 || return 1
	. /usr/lib/open-hotspot/opennds.sh
	opennds_reload || return 1
	"$UCI_BIN" set open-hotspot.global.local_fas_enabled='0' || return 1
	"$UCI_BIN" commit open-hotspot || return 1
	printf 'local_fas_enabled=0\nrestored=%s\n' "$dir"
}

status() {
	printf 'local_fas_enabled=%s\n' "$($UCI_BIN -q get open-hotspot.global.local_fas_enabled || true)"
	printf 'fas_mode=%s\n' "$($UCI_BIN -q get open-hotspot.global.fas_mode || true)"
	printf 'fas_port=%s\n' "$($UCI_BIN -q get open-hotspot.global.fas_port || true)"
	printf 'fas_path=%s\n' "$($UCI_BIN -q get open-hotspot.global.fas_path || true)"
	printf 'activation_checkpoint=%s\n' "$(cat "$BACKUP_ROOT/latest" 2>/dev/null || true)"
}

case "${1:-}" in
	enable) activate ;;
	rollback) rollback ;;
	status) status ;;
	*) echo 'usage: activate-local-fas.sh {enable|rollback|status}' >&2; exit 2 ;;
esac
