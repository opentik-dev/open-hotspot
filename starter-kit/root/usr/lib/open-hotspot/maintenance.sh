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
_valid_int "$RETENTION_DAYS" || RETENTION_DAYS=90
_valid_int "$LOG_CAP_KB" || LOG_CAP_KB=256
[ "$LOG_CAP_KB" -ge 1 ] || LOG_CAP_KB=1
cutoff=$(date -u -d "-${RETENTION_DAYS} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

if [ -n "$cutoff" ]; then
	sqlite3 -batch "$DB_PATH" "DELETE FROM usage_periods WHERE closed=1 AND period_end < '$cutoff';"
	sqlite3 -batch "$DB_PATH" "DELETE FROM admin_events WHERE ts < '$cutoff';"
	sqlite3 -batch "$DB_PATH" "DELETE FROM usage_events WHERE received_at < '$cutoff';"
fi

sqlite3 -batch "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" ||
	db_log_event maintenance_checkpoint_failed '' 'wal-checkpoint-failed' || true

# VACUUM rewrites the whole database. Run it only when free pages indicate
# meaningful fragmentation; a daily checkpoint remains cheap and predictable.
fragmentation=$(sqlite3 -batch "$DB_PATH" \
	"SELECT page_count || '|' || freelist_count FROM pragma_page_count(), pragma_freelist_count();" \
	2>/dev/null || true)
page_count=$(printf '%s' "$fragmentation" | cut -d'|' -f1)
freelist_count=$(printf '%s' "$fragmentation" | cut -d'|' -f2)
if _valid_int "$page_count" && _valid_int "$freelist_count" \
	&& [ "$page_count" -gt 0 ] \
	&& [ $((freelist_count * 100)) -ge $((page_count * 20)) ]; then
	sqlite3 -batch "$DB_PATH" "VACUUM;" ||
		db_log_event maintenance_vacuum_failed '' 'vacuum-failed' || true
fi

LOG=/var/log/open-hotspot.log
if [ -f "$LOG" ]; then
	size_kb=$(du -k "$LOG" 2>/dev/null | cut -f1)
	if [ -n "$size_kb" ] && [ "$size_kb" -gt "$LOG_CAP_KB" ]; then
		tail -c "$(( LOG_CAP_KB / 2 ))k" "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
	fi
fi

exit 0
