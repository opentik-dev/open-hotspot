#!/bin/sh
# diagnose.sh — read-only integration health report for Open-HotSpot.
#
# This command never changes UCI, restarts services, edits the firewall, or
# prints FAS keys/PINs. It is intended for factory-reset acceptance and for
# collecting a repeatable boundary report when LuCI and openNDS disagree.

DIAG_UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
DIAG_DB="${OPEN_HOTSPOT_DB_PATH:-/etc/open-hotspot/hotspot.db}"
DIAG_NDSCTL="${OPEN_HOTSPOT_NDSCTL_BIN:-ndsctl}"
DIAG_TMP="/tmp/open-hotspot-diagnose.$$"
diag_failures=0
diag_warnings=0

diag_have() {
	command -v "$1" >/dev/null 2>&1
}

diag_ok() {
	printf 'OK %s\n' "$1"
}

diag_warn() {
	diag_warnings=$((diag_warnings + 1))
	printf 'WARN %s\n' "$1"
}

diag_fail() {
	diag_failures=$((diag_failures + 1))
	printf 'FAIL %s\n' "$1"
}

diag_uci_get() {
	"$DIAG_UCI_BIN" -q get "$1" 2>/dev/null || true
}

diag_service_running() {
	service="$1"
	[ -x "/etc/init.d/$service" ] || return 1
	if "/etc/init.d/$service" status >/dev/null 2>&1; then
		return 0
	fi
	pidof "$service" >/dev/null 2>&1
}

diag_db_counts() {
	[ -r "$DIAG_DB" ] || {
		diag_fail 'database=missing'
		return 0
	}
	counts=$(sqlite3 -separator '|' "$DIAG_DB" \
		"select (select count(*) from auth_transactions where state=\"pending\"),\
(select count(*) from devices where status=\"active\"),\
(select count(*) from active_sessions where state=\"active\"),\
(select count(*) from usage_events);" 2>/dev/null) || {
		diag_fail 'database=query-failed'
		return 0
	}
	printf 'INFO database_counts=pending|active_devices|active_sessions|usage_events:%s\n' "$counts"
	old_ifs="$IFS"
	IFS='|'
	read -r pending devices sessions usage <<EOF
$counts
EOF
	IFS="$old_ifs"
	if [ "${sessions:-0}" -gt 0 ] && [ "${devices:-0}" -eq 0 ]; then
		diag_fail 'database=inconsistent-active-session-without-device'
	fi
	if [ "${pending:-0}" -gt 0 ] && [ "${sessions:-0}" -eq 0 ]; then
		diag_warn 'integration=pending-auth-without-manager-session'
	fi
}

diag_nds_clients() {
	diag_have "$DIAG_NDSCTL" || {
		diag_fail 'opennds=ndsctl-missing'
		return 0
	}
	status_file="$DIAG_TMP/nds-status"
	mkdir -p "$DIAG_TMP"
	if ! "$DIAG_NDSCTL" status >"$status_file" 2>/dev/null; then
		diag_fail 'opennds=ndsctl-status-failed'
		return 0
	fi
	version=$(sed -n 's/^Version: //p' "$status_file" | sed -n '1p')
	clients=$(sed -n 's/^Current clients: //p' "$status_file" | sed -n '1p')
	state=$(grep -E '^[[:space:]]*State:' "$status_file" | sed -n '1p' | sed 's/^[[:space:]]*State: //')
	printf 'INFO opennds_version=%s\n' "${version:-unknown}"
	printf 'INFO opennds_current_clients=%s\n' "${clients:-unknown}"
	[ -n "$version" ] || diag_fail 'opennds=version-unavailable'
	[ -n "$clients" ] || diag_warn 'opennds=current-client-count-unavailable'
	[ -n "$state" ] && printf 'INFO first_client_state=%s\n' "$state"
	if [ "${clients:-0}" -gt 0 ] && [ "${state:-}" = Authenticated ]; then
		sessions=$(sqlite3 "$DIAG_DB" 'select count(*) from active_sessions where state="active";' 2>/dev/null || printf 0)
		[ "$sessions" -gt 0 ] || diag_warn 'integration=opennds-authenticated-without-manager-session'
	fi
}

diag_fas() {
	remote_ip=$(diag_uci_get opennds.@opennds[0].fasremoteip)
	remote_fqdn=$(diag_uci_get opennds.@opennds[0].fasremotefqdn)
	gateway_fqdn=$(diag_uci_get opennds.@opennds[0].gatewayfqdn)
	fas_port=$(diag_uci_get opennds.@opennds[0].fasport)
	fas_path=$(diag_uci_get opennds.@opennds[0].faspath)
	secure=$(diag_uci_get opennds.@opennds[0].fas_secure_enabled)
	custom=$(diag_uci_get opennds.@opennds[0].custombinauth)
	printf 'INFO fasremoteip=%s\n' "$( [ -n "$remote_ip" ] && printf configured || printf unset )"
	printf 'INFO fasremotefqdn=%s gatewayfqdn=%s fasport=%s faspath=%s secure=%s\n' \
		"${remote_fqdn:-unset}" "${gateway_fqdn:-unset}" "${fas_port:-unset}" \
		"${fas_path:-unset}" "${secure:-unset}"
	[ -z "$remote_ip" ] || diag_warn 'fas=remote-ip-configured-address-dependency'
	[ "$remote_fqdn" = status.client ] || diag_fail 'fas=dynamic-fqdn-not-status.client'
	[ "$gateway_fqdn" = status.client ] || diag_fail 'fas=gateway-fqdn-not-status.client'
	[ "$fas_port" = 2080 ] || diag_fail 'fas=expected-local-port-2080'
	[ "$fas_path" = /nds/fas.php ] || diag_fail 'fas=unexpected-path'
	[ "$secure" = 1 ] || diag_fail 'fas=secure-level-not-1'
	[ "$custom" = /usr/lib/opennds/custombinauth.sh ] || diag_fail 'binauth=custom-hook-not-configured'
	[ -r /usr/lib/opennds/custombinauth.sh ] || diag_fail 'binauth=custom-script-missing'
	if [ -r /usr/lib/opennds/binauth_log.sh ]; then
		grep -F 'custombinauthpath=$(uci -q get opennds.@opennds[0].custombinauth' \
			/usr/lib/opennds/binauth_log.sh >/dev/null 2>&1 ||
			diag_warn 'binauth=dispatcher-uci-fallback-not-installed'
	else
		diag_fail 'binauth=stock-dispatcher-missing'
	fi
}

diag_uhttpd() {
	mkdir -p "$DIAG_TMP"
	if diag_service_running uhttpd; then
		diag_ok 'uhttpd=running'
	else
		diag_fail 'uhttpd=not-running'
	fi
	listen=$(diag_uci_get uhttpd.open_hotspot_fas.listen_http)
	printf 'INFO uhttpd_fas_listen=%s\n' "${listen:-unset}"
	printf '%s\n' "$listen" | grep -F ':2080' >/dev/null 2>&1 ||
		diag_fail 'uhttpd=fas-listener-2080-not-configured'
	if diag_have wget; then
		probe="$DIAG_TMP/fas-probe"
		probe_log="$DIAG_TMP/fas-probe.log"
		if wget -T 5 -O "$probe" 'http://127.0.0.1:2080/nds/fas.php' >"$probe_log" 2>&1; then
			grep -F 'Open-HotSpot' "$probe" >/dev/null 2>&1 ||
				diag_warn 'fas=http-response-missing-open-hotspot-marker'
			diag_ok 'fas=http-local-listener-responds'
		elif grep -F 'HTTP error 400' "$probe_log" >/dev/null 2>&1; then
			# A bare FAS endpoint has no openNDS query payload. HTTP 400 proves
			# that uhttpd and PHP reached the endpoint; a transport failure does not.
			diag_ok 'fas=http-local-listener-responds-with-expected-bare-request-400'
		else
			diag_fail 'fas=http-local-listener-no-response'
		fi
	else
		diag_warn 'fas=wget-not-installed-probe-skipped'
	fi
}

diag_cleanup() {
	rm -rf "$DIAG_TMP"
}

open_hotspot_diagnose() {
	trap diag_cleanup EXIT INT TERM
	printf 'OPEN_HOTSPOT_DIAGNOSTIC_V1\n'
	printf 'INFO gateway_interface=%s\n' "$(diag_uci_get opennds.@opennds[0].gatewayinterface)"
	printf 'INFO lan_addresses_discovered=\n'
	ip -4 addr show 2>/dev/null | awk '$1 == "inet" {print "INFO " $2 " dev " $NF}'
	if diag_service_running opennds; then
		diag_ok 'opennds=running'
	else
		diag_fail 'opennds=not-running'
	fi
	diag_fas
	diag_uhttpd
	diag_nds_clients
	diag_db_counts
	printf 'SUMMARY failures=%s warnings=%s\n' "$diag_failures" "$diag_warnings"
	[ "$diag_failures" -eq 0 ]
}

open_hotspot_diagnose
