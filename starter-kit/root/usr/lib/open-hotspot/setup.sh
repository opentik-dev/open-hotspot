#!/bin/sh
# setup.sh — restartable base setup state machine for a clean router.
#
# This stage initializes the manager and records blockers. It intentionally
# does not switch an existing external FAS, edit openNDS, or replace dnsmasq.
# Local-FAS activation belongs to a later guided action after preflight and
# explicit administrator confirmation.

SETUP_UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
SETUP_DB_HELPER="${OPEN_HOTSPOT_DB_HELPER:-/usr/lib/open-hotspot/db.sh}"
SETUP_PREFLIGHT="${OPEN_HOTSPOT_PREFLIGHT:-/usr/lib/open-hotspot/preflight.sh}"

setup_uci_get() {
	"$SETUP_UCI_BIN" -q get "open-hotspot.global.$1" 2>/dev/null || true
}

setup_uci_set() {
	"$SETUP_UCI_BIN" set "open-hotspot.global.$1=$2"
}

setup_state() {
	setup_uci_get setup_state
}

setup_record() {
	state="$1"; detail="${2:-}"
	setup_uci_set setup_state "$state" || return 1
	setup_uci_set setup_last_error "$detail" || return 1
	"$SETUP_UCI_BIN" commit open-hotspot
}

setup_ensure_policy_defaults() {
	[ -n "$(setup_uci_get client_network)" ] || setup_uci_set client_network '' || return 1
	[ -n "$(setup_uci_get client_router_access)" ] || setup_uci_set client_router_access deny || return 1
	[ -n "$(setup_uci_get session_restore)" ] || setup_uci_set session_restore disabled || return 1
	"$SETUP_UCI_BIN" commit open-hotspot
}

setup_base() {
	. "$SETUP_DB_HELPER"
	. "$SETUP_PREFLIGHT"
	setup_ensure_policy_defaults || return 1

	if ! open_hotspot_preflight; then
		setup_record PREFLIGHT_FAILED 'preflight-blocked' || true
		return 1
	fi
	setup_record PREFLIGHT_OK '' || return 1

	if ! db_init; then
		setup_record DATABASE_FAILED 'database-init-failed' || true
		return 1
	fi
	setup_record BASE_READY '' || return 1
	return 0
}

setup_status() {
	printf 'state=%s\n' "$(setup_state)"
	printf 'fas_mode=%s\n' "$(setup_uci_get fas_mode)"
	printf 'fas_port=%s\n' "$(setup_uci_get fas_port)"
	printf 'fas_path=%s\n' "$(setup_uci_get fas_path)"
	printf 'local_fas_enabled=%s\n' "$(setup_uci_get local_fas_enabled)"
	printf 'session_restore=%s\n' "$(setup_uci_get session_restore)"
	printf 'client_network=%s\n' "$(setup_uci_get client_network)"
	printf 'client_router_access=%s\n' "$(setup_uci_get client_router_access)"
	printf 'last_error=%s\n' "$(setup_uci_get setup_last_error)"
}

case "${1:-}" in
	base) setup_base ;;
	status) setup_status ;;
	*)
		echo 'usage: setup.sh {base|status}' >&2
		exit 2
		;;
esac
