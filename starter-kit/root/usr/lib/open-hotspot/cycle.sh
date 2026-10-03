#!/bin/sh
# cycle.sh — runs every `check_interval` seconds (floor 60, default 300),
# invoked by cron, guarded by flock so overlapping runs are skipped, not
# queued (Constitution Article II). Does exactly three things — nothing
# that isn't required on every tick belongs here (see maintenance.sh for
# the once-daily housekeeping).
#
LOCK=/var/run/open-hotspot-cycle.lock
exec 9>"$LOCK"
flock -n 9 || exit 0   # a previous run is still going: skip this tick, don't stack

. /usr/lib/open-hotspot/db.sh
. /usr/lib/open-hotspot/period.sh
. /usr/lib/open-hotspot/opennds.sh
. /usr/lib/open-hotspot/quota.sh

ensure_opennds_runtime() {
	[ "$(uci -q get open-hotspot.global.local_fas_enabled || true)" = 1 ] || return 0
	validate_rc=0
	if opennds_validate_config; then
		return 0
	fi
	validate_rc=$?

	# If openNDS process is still running, avoid an aggressive reload that would
	# tear down live sessions. Allow one brief retry in case ndsctl was transiently busy.
	if pidof opennds >/dev/null 2>&1; then
		sleep 1
		if opennds_validate_config; then
			return 0
		fi
	fi

	reload_rc=0
	opennds_reload || reload_rc=$?
	if [ "$reload_rc" -eq 0 ]; then
		db_log_event opennds_recovered '' 'runtime-readiness-recovered' || true
		return 0
	fi
	db_log_event opennds_not_ready '' "nds:validate=$validate_rc:reload=$reload_rc" || true
	return 1
}

# Do not mutate sessions while the captive daemon is unavailable. Attempt one
# bounded recovery; new clients remain fail-closed until ndsctl is ready.
ensure_opennds_runtime || exit 0

db_expire_pending_auth ||
	db_log_event auth_expiry_failed '' 'pending-auth-expiry-failed' || true

# Retry the one-per-boot manager-owned restore if openNDS was not ready during
# init ordering. The helper uses SQLite identity/policy and the verified
# ndsctl adapter; it never runs from BinAuth and never keys on an IP address.
if [ -x /usr/lib/open-hotspot/session-restore.sh ]; then
	restore_rc=0
	/usr/lib/open-hotspot/session-restore.sh restore >/dev/null 2>&1 || restore_rc=$?
	[ "$restore_rc" -eq 0 ] ||
		db_log_event session_restore_failed '' "restore:rc=$restore_rc" || true
	reconcile_rc=0
	/usr/lib/open-hotspot/session-restore.sh reconcile >/dev/null 2>&1 || reconcile_rc=$?
	[ "$reconcile_rc" -eq 0 ] ||
		db_log_event session_reconcile_failed '' "reconcile:rc=$reconcile_rc" || true
fi

now_epoch=$(date -u '+%s')

# 1) Close any usage_periods whose period_end has passed; open the next one
#    implicitly happens on next accrual/auth (rows are created on demand).
#    For accounts with a currently-connected device, reissue an updated
#    ceiling so the live session sees the new period's fresh budget
#    (FR-006 — no forced disconnect purely for a period boundary).
sqlite3 -batch "$DB_PATH" "UPDATE usage_periods SET closed=1, closed_at=datetime('now')
	WHERE closed=0 AND julianday(period_end) <= julianday('now');" ||
	db_log_event cycle_database_error '' 'period-close-failed' || true

sqlite3 -batch "$DB_PATH" "
	SELECT DISTINCT d.mac, a.id, a.profile_id, COALESCE(a.renewed_at,''),
	       COALESCE(s.policy_period_start,'')
	FROM devices d
	JOIN accounts a ON a.id = d.account_id
	JOIN active_sessions s ON s.device_id = d.id
	WHERE d.status='active' AND a.status='active' AND a.deleted_at IS NULL
	AND s.state='active';" | while IFS='|' read -r mac acct_id profile_id renewed_at policy_period_start; do
	# The policy is refreshed once for a newly entered period. A failed
	# refresh leaves the marker unchanged, so the next tick retries it.
	[ -n "$mac" ] || continue
	prof=$(db_profile_get "$profile_id")
	period_type=$(printf '%s' "$prof" | cut -d'|' -f1)
	time_limit=$(printf '%s' "$prof"  | cut -d'|' -f2)
	up_vol=$(printf '%s' "$prof"      | cut -d'|' -f3)
	down_vol=$(printf '%s' "$prof"    | cut -d'|' -f4)
	up_rate=$(printf '%s' "$prof"     | cut -d'|' -f5)
	down_rate=$(printf '%s' "$prof"   | cut -d'|' -f6)

	window=$(period_window_effective "$period_type" "$renewed_at" "$now_epoch") || {
		db_log_event period_window_error "$acct_id" "$mac" || true
		continue
	}
	period_start=$(printf '%s' "$window" | cut -f1)
	used=$(db_usage_get "$acct_id" "$period_start")
	used_s=$(printf '%s' "$used" | cut -d'|' -f1); used_s=${used_s:-0}
	used_up=$(printf '%s' "$used" | cut -d'|' -f2); used_up=${used_up:-0}
	used_down=$(printf '%s' "$used" | cut -d'|' -f3); used_down=${used_down:-0}

	remaining=$(quota_remaining "$time_limit" "$used_s" "$up_vol" "$used_up" "$down_vol" "$used_down") || {
		db_log_event cycle_quota_error "$acct_id" "$mac" || true
		continue
	}
	remaining_time=$(printf '%s' "$remaining" | cut -d'|' -f1)
	remaining_up=$(printf '%s' "$remaining" | cut -d'|' -f2)
	remaining_down=$(printf '%s' "$remaining" | cut -d'|' -f3)
	exhausted=$(printf '%s' "$remaining" | cut -d'|' -f4)
	if [ "$exhausted" = '1' ]; then
		deauth_rc=0
		opennds_deauth "$mac" 2>/dev/null || deauth_rc=$?
		if [ "$deauth_rc" -ne 0 ]; then
			db_log_event quota_deauth_failed "$acct_id" "quota:exhausted:deauth_rc=$deauth_rc" || true
		fi
		continue
	fi

	[ "$policy_period_start" = "$period_start" ] && continue

	if opennds_apply_session_policy "$mac" "$remaining_time" "$up_rate" "$down_rate" "$remaining_up" "$remaining_down" 2>/dev/null; then
		if ! sqlite3 -batch "$DB_PATH" "UPDATE active_sessions SET policy_period_start='$(_sql_escape "$period_start")' WHERE state='active' AND device_id IN (SELECT id FROM devices WHERE mac='$mac' COLLATE NOCASE);"; then
			db_log_event policy_marker_failed "$acct_id" "$mac" || true
		fi
	else
		# Preserve the live openNDS session, but make a bounded, non-secret
		# diagnostic visible to the status/history layer.
		db_log_event policy_refresh_failed "$acct_id" "policy:period=$period_type:window=$period_start" || true
	fi
done

# 2) Deauth devices whose account's hard expiry has passed while connected.
sqlite3 -batch "$DB_PATH" "
	SELECT d.mac FROM devices d JOIN accounts a ON a.id = d.account_id
	JOIN active_sessions s ON s.device_id = d.id
	WHERE d.status='active' AND a.status='active' AND s.state='active'
	  AND a.expires_at IS NOT NULL AND julianday(a.expires_at) <= julianday('now');" \
| while read -r mac; do
	if [ -n "$mac" ]; then
		expiry_deauth_rc=0
		opennds_deauth "$mac" 2>/dev/null || expiry_deauth_rc=$?
		[ "$expiry_deauth_rc" -eq 0 ] ||
			db_log_event expiry_deauth_failed '' "expiry:deauth_rc=$expiry_deauth_rc" || true
	fi
done

exit 0
