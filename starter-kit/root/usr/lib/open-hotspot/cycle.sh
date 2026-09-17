#!/bin/sh
# cycle.sh — runs every `check_interval` seconds (floor 60, default 300),
# invoked by cron, guarded by flock so overlapping runs are skipped, not
# queued (Constitution Article II). Does exactly three things — nothing
# that isn't required on every tick belongs here (see maintenance.sh for
# the once-daily housekeeping).
#
# T002/T004/T005 are open; opennds.sh fails closed until the target contract
# and units are verified.

LOCK=/var/run/open-hotspot-cycle.lock
exec 9>"$LOCK"
flock -n 9 || exit 0   # a previous run is still going: skip this tick, don't stack

. /usr/lib/open-hotspot/db.sh
. /usr/lib/open-hotspot/period.sh
. /usr/lib/open-hotspot/opennds.sh

now=$(date -u '+%Y-%m-%d %H:%M:%S')

# 1) Close any usage_periods whose period_end has passed; open the next one
#    implicitly happens on next accrual/auth (rows are created on demand).
#    For accounts with a currently-connected device, reissue an updated
#    ceiling so the live session sees the new period's fresh budget
#    (FR-006 — no forced disconnect purely for a period boundary).
sqlite3 -batch "$DB_PATH" "UPDATE usage_periods SET closed=1
	WHERE closed=0 AND period_end <= '$now';"

sqlite3 -batch "$DB_PATH" "
	SELECT d.mac, a.id, a.profile_id
	FROM devices d
	JOIN accounts a ON a.id = d.account_id
	WHERE d.status='active';" | while IFS='|' read -r mac acct_id profile_id; do
	[ -n "$mac" ] || continue
	prof=$(db_profile_get "$profile_id")
	period_type=$(printf '%s' "$prof" | cut -d'|' -f1)
	time_limit=$(printf '%s' "$prof"  | cut -d'|' -f2)
	up_vol=$(printf '%s' "$prof"      | cut -d'|' -f3)
	down_vol=$(printf '%s' "$prof"    | cut -d'|' -f4)
	up_rate=$(printf '%s' "$prof"     | cut -d'|' -f5)
	down_rate=$(printf '%s' "$prof"   | cut -d'|' -f6)

	bounds=$(period_bounds "$period_type")
	period_start=$(printf '%s' "$bounds" | cut -f1)
	used=$(db_usage_get "$acct_id" "$period_start")
	used_s=$(printf '%s' "$used" | cut -d'|' -f1); used_s=${used_s:-0}
	used_up=$(printf '%s' "$used" | cut -d'|' -f2); used_up=${used_up:-0}
	used_down=$(printf '%s' "$used" | cut -d'|' -f3); used_down=${used_down:-0}

	remaining_time=$time_limit;  [ "$time_limit" -gt 0 ] && remaining_time=$(( time_limit - used_s ))
	remaining_up=$up_vol;        [ "$up_vol" -gt 0 ]     && remaining_up=$(( up_vol - used_up ))
	remaining_down=$down_vol;    [ "$down_vol" -gt 0 ]   && remaining_down=$(( down_vol - used_down ))

	opennds_apply_session_policy "$mac" "$remaining_time" "$up_rate" "$down_rate" "$remaining_up" "$remaining_down" 2>/dev/null || true
done

# 2) Deauth devices whose account's hard expiry has passed while connected.
today=$(date -u +%Y-%m-%d)
sqlite3 -batch "$DB_PATH" "
	SELECT d.mac FROM devices d JOIN accounts a ON a.id = d.account_id
	WHERE d.status='active' AND a.expires_at IS NOT NULL AND a.expires_at < '$today';" \
| while read -r mac; do
	[ -n "$mac" ] && opennds_deauth "$mac" 2>/dev/null || true
done

exit 0
