#!/bin/sh
# maintenance.sh — runs once daily via cron, flock guarded. Deliberately
# separate from cycle.sh: "if a function isn't required for correctness
# on every tick, it doesn't run on every tick" (research.md).

LOCK=/var/run/open-hotspot-maintenance.lock
exec 9>"$LOCK"
flock -n 9 || exit 0

. /usr/lib/open-hotspot/db.sh

RETENTION_DAYS=$(uci -q get open-hotspot.global.history_retention || echo 90)
LOG_CAP_KB=$(uci -q get open-hotspot.global.log_retention_kb || echo 256)
cutoff=$(date -u -d "-${RETENTION_DAYS} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

if [ -n "$cutoff" ]; then
	sqlite3 -batch "$DB_PATH" "DELETE FROM usage_periods WHERE closed=1 AND period_end < '$cutoff';"
	sqlite3 -batch "$DB_PATH" "DELETE FROM admin_events WHERE ts < '$cutoff';"
	sqlite3 -batch "$DB_PATH" "DELETE FROM usage_events WHERE received_at < '$cutoff';"
fi

sqlite3 -batch "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);"
sqlite3 -batch "$DB_PATH" "VACUUM;"

LOG=/var/log/open-hotspot.log
if [ -f "$LOG" ]; then
	size_kb=$(du -k "$LOG" 2>/dev/null | cut -f1)
	if [ -n "$size_kb" ] && [ "$size_kb" -gt "$LOG_CAP_KB" ]; then
		tail -c "$(( LOG_CAP_KB / 2 ))k" "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
	fi
fi

exit 0
