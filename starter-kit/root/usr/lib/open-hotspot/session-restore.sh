#!/bin/sh
# session-restore.sh — optional reboot restore outside BinAuth.
#
# The manager owns the persistent identity/policy state in SQLite. When enabled,
# active sessions from the previous boot are re-authorised once after openNDS
# becomes ready, using the verified ndsctl adapter and the stored session key.
# This deliberately does not use a client IP, does not run inside BinAuth, and
# never restores a suspended/expired/exhausted account.

UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"
DB_HELPER="${OPEN_HOTSPOT_DB_HELPER:-/usr/lib/open-hotspot/db.sh}"
PERIOD_HELPER="${OPEN_HOTSPOT_PERIOD_HELPER:-/usr/lib/open-hotspot/period.sh}"
NDS_HELPER="${OPEN_HOTSPOT_NDS_HELPER:-/usr/lib/open-hotspot/opennds.sh}"
QUOTA_HELPER="${OPEN_HOTSPOT_QUOTA_HELPER:-/usr/lib/open-hotspot/quota.sh}"
MARKER="${OPEN_HOTSPOT_SESSION_RESTORE_MARKER:-/var/run/open-hotspot-session-restore.done}"

mode() {
	"$UCI_BIN" -q get open-hotspot.global.session_restore 2>/dev/null || printf 'disabled\n'
}

opennds_pid() {
	pidof opennds 2>/dev/null | awk '{print $1}'
}

valid_mode() {
	case "$1" in enabled|disabled) return 0 ;; *) return 1 ;; esac
}

set_mode() {
	valid_mode "$1" || return 1
	"$UCI_BIN" set "open-hotspot.global.session_restore=$1" || return 1
	"$UCI_BIN" commit open-hotspot || return 1
	if [ "$1" = enabled ]; then
		rm -f "$MARKER"
	else
		mkdir -p "$(dirname "$MARKER")" || return 1
		printf '%s\n' "$(opennds_pid)" > "$MARKER" || return 1
	fi
}

restore_one() {
	mac="$1"; account_id="$2"; profile_id="$3"; session_key="$4"; renewed_at="${5:-}"
	prof=$(db_profile_get "$profile_id") || return 1
	period_type=$(printf '%s' "$prof" | cut -d'|' -f1)
	time_limit=$(printf '%s' "$prof" | cut -d'|' -f2)
	upload_limit=$(printf '%s' "$prof" | cut -d'|' -f3)
	download_limit=$(printf '%s' "$prof" | cut -d'|' -f4)
	upload_rate=$(printf '%s' "$prof" | cut -d'|' -f5)
	download_rate=$(printf '%s' "$prof" | cut -d'|' -f6)
	[ -n "$period_type" ] || return 1

	# The account renewal is part of the policy identity.  Restoring against
	# the calendar window would resurrect a session with an old quota window.
	window=$(period_window_effective "$period_type" "$renewed_at" "$RESTORE_NOW") || return 1
	period_start=$(printf '%s' "$window" | cut -f1)
	used=$(db_usage_get "$account_id" "$period_start") || return 1
	used_time=$(printf '%s' "$used" | cut -d'|' -f1); used_time=${used_time:-0}
	used_upload=$(printf '%s' "$used" | cut -d'|' -f2); used_upload=${used_upload:-0}
	used_download=$(printf '%s' "$used" | cut -d'|' -f3); used_download=${used_download:-0}

	remaining=$(quota_remaining "$time_limit" "$used_time" "$upload_limit" \
		"$used_upload" "$download_limit" "$used_download") || return 1
	remaining_time=$(printf '%s' "$remaining" | cut -d'|' -f1)
	remaining_upload=$(printf '%s' "$remaining" | cut -d'|' -f2)
	remaining_download=$(printf '%s' "$remaining" | cut -d'|' -f3)
	exhausted=$(printf '%s' "$remaining" | cut -d'|' -f4)
	if [ "$exhausted" = 1 ]; then
		# Do not restore a session whose current manager policy is exhausted.
		opennds_deauth "$mac" >/dev/null 2>&1 || true
		return 0
	fi

	opennds_apply_session_policy "$mac" "$remaining_time" "$upload_rate" \
		"$download_rate" "$remaining_upload" "$remaining_download" "$session_key" \
		>/dev/null 2>&1
}

restore_sessions() {
	[ "$(mode)" = enabled ] || return 0
	. "$DB_HELPER"
	. "$PERIOD_HELPER"
	. "$NDS_HELPER"
	. "$QUOTA_HELPER"
	RESTORE_NOW=$(date -u '+%s') || return 1
	opennds_validate_config || return 1
	current_pid=$(opennds_pid)
	[ -n "$current_pid" ] || return 1
	if [ -r "$MARKER" ] && grep -Fx "$current_pid" "$MARKER" >/dev/null 2>&1; then
		return 0
	fi

	rows=$(sqlite3 -batch -separator '|' "$DB_PATH" \
		"SELECT DISTINCT d.mac, a.id, a.profile_id, s.session_key,
		                COALESCE(a.renewed_at,'')
		   FROM devices d
		   JOIN accounts a ON a.id=d.account_id
		   JOIN active_sessions s ON s.device_id=d.id
		  WHERE d.status='active' AND a.status='active'
		    AND a.deleted_at IS NULL AND s.state='active';") || return 1

	failed=0
	while IFS='|' read -r mac account_id profile_id session_key renewed_at; do
		[ -n "$mac" ] || continue
		if ! restore_one "$mac" "$account_id" "$profile_id" "$session_key" "$renewed_at"; then
			failed=1
		fi
	done <<EOF
$rows
EOF
	[ "$failed" -eq 0 ] || return 1
	mkdir -p "$(dirname "$MARKER")" || return 1
	printf '%s\n' "$current_pid" > "$MARKER"
}

status() {
	printf 'session_restore=%s\n' "$(mode)"
	if [ -e "$MARKER" ]; then
		printf 'restore_attempted=1\n'
		printf 'restore_pid=%s\n' "$(cat "$MARKER")"
	else
		printf 'restore_attempted=0\n'
	fi
}

reconcile_stale() {
	# Disabled restore means a previous boot's manager rows are not entitled to
	# remain live forever. Only reconcile when the daemon is healthy and reports
	# zero clients; an unreadable status or any live client fails closed.
	[ "$(mode)" = disabled ] || return 0
	. "$DB_HELPER"
	. "$NDS_HELPER"
	opennds_validate_config || return 1
	clients=$(opennds_current_clients) || return 1
	[ "$clients" -eq 0 ] || return 0
	closed=$(sqlite3 -batch -noheader "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE active_sessions
	   SET state='closed', closed_at=COALESCE(closed_at,datetime('now')),
	       last_seen_at=datetime('now')
	 WHERE state='active';
	SELECT changes(); COMMIT;") || return 1
	case "$closed" in
		0) ;;
		*[!0-9]*) return 1 ;;
		*) db_log_event stale_session_reconciled '' 'opennds-reported-zero-clients' || true ;;
	esac
}

case "${1:-}" in
	apply) set_mode "${2:-}" ;;
	restore) restore_sessions ;;
	reconcile) reconcile_stale ;;
	status) status ;;
	*) printf 'usage: session-restore.sh {apply enabled|disabled|restore|reconcile|status}\n' >&2; exit 2 ;;
esac
