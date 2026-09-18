#!/bin/sh
# db.sh — Open-HotSpot SQLite access layer.
#
# The target uses sqlite3-cli, not a shell-reachable prepared-statement API.
# Every value therefore goes through a strict validator where possible and
# SQL single-quote escaping where free text is intentionally allowed. This is
# validation plus escaping; it is not prepared-statement binding.

DB_PATH="${OPEN_HOTSPOT_DB_PATH:-/etc/open-hotspot/hotspot.db}"
SCHEMA_PATH="${OPEN_HOTSPOT_SCHEMA_PATH:-/usr/lib/open-hotspot/schema.sql}"
DB_SCHEMA_VERSION=3
DB_MIGRATIONS_PATH="${OPEN_HOTSPOT_MIGRATIONS_PATH:-/usr/lib/open-hotspot/migrations}"

_db_is_empty() {
	[ "$(sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" \
		"SELECT count(*) FROM sqlite_master WHERE type IN ('table','index','trigger','view') AND name NOT LIKE 'sqlite_%';" 2>/dev/null || echo 1)" = "0" ]
}

_db_version_is_valid() {
	case "$1" in ''|*[!0-9]*) return 1 ;; esac
	[ "$1" -ge 1 ]
}

# Apply numbered SQL migrations one version at a time. Each migration must be
# self-contained, transactional, and insert its resulting version into
# schema_meta. Missing or skipped migrations fail closed.
db_migrate() {
	current="$1"
	_valid_int "$current" || return 1
	[ "$current" -le "$DB_SCHEMA_VERSION" ] || return 1

	while [ "$current" -lt "$DB_SCHEMA_VERSION" ]; do
		next=$((current + 1))
		migration="$DB_MIGRATIONS_PATH/$(printf '%03d' "$next").sql"
		[ -r "$migration" ] || {
			echo "open-hotspot: missing migration for schema version $next" >&2
			return 1
		}
		sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" < "$migration" || return 1
		current=$(db_schema_version) || return 1
		[ "$current" = "$next" ] || {
			echo "open-hotspot: migration did not reach schema version $next" >&2
			return 1
		}
	done
}

db_init() {
	mkdir -p "$(dirname "$DB_PATH")" || return 1
	command -v sqlite3 >/dev/null 2>&1 || {
		echo "open-hotspot: sqlite3-cli is required" >&2
		return 1
	}

	if [ ! -f "$DB_PATH" ] || _db_is_empty; then
		sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" < "$SCHEMA_PATH" || return 1
	else
		version=$(db_schema_version 2>/dev/null || true)
		_db_version_is_valid "$version" || {
			echo "open-hotspot: unversioned database; refusing implicit migration" >&2
			return 1
		}
		[ "$version" -le "$DB_SCHEMA_VERSION" ] || {
			echo "open-hotspot: database schema version $version is newer than supported $DB_SCHEMA_VERSION" >&2
			return 1
		}
		db_migrate "$version" || return 1
	fi

	[ "$(db_schema_version)" = "$DB_SCHEMA_VERSION" ]
}

_valid_ident() {
	case "$1" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; *) return 0 ;; esac
}

_valid_mac() {
	case "$1" in
		[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
		*) return 1 ;;
	esac
}

_valid_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
_valid_epoch() { _valid_int "$1" && [ "$1" -le 2147483647 ]; }
_valid_hex32() {
	[ "${#1}" -eq 32 ] || return 1
	case "$1" in *[!0-9A-Fa-f]*) return 1 ;; *) return 0 ;; esac
}
_sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }
_sql() { sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" "$1"; }

db_schema_version() {
	_sql "SELECT version FROM schema_meta ORDER BY version DESC LIMIT 1;"
}

db_account_get_by_username() {
	u="$1"; _valid_ident "$u" || return 1
	_sql "SELECT id, pin_hash, pin_salt, pin_iter, profile_id, status, expires_at
	       FROM accounts WHERE username = '$(_sql_escape "$u")' AND deleted_at IS NULL LIMIT 1;"
}

db_account_get_profile_id() {
	acct="$1"; _valid_int "$acct" || return 1
	_sql "SELECT profile_id FROM accounts WHERE id = $acct LIMIT 1;"
}

db_device_get_by_mac() {
	mac="$1"; _valid_mac "$mac" || return 1
	_sql "SELECT id, account_id, status FROM devices WHERE mac = '$mac' LIMIT 1;"
}

db_device_count_active() {
	acct="$1"; _valid_int "$acct" || return 1
	_sql "SELECT count(*) FROM active_sessions WHERE account_id = $acct AND state='active';"
}

db_device_upsert() {
	acct="$1"; mac="$2"; hostname="$3"
	_valid_int "$acct" || return 1
	_valid_mac "$mac" || return 1
	_sql "INSERT INTO devices (account_id, mac, hostname, status, last_seen, updated_at)
	       VALUES ($acct, '$mac', '$(_sql_escape "$hostname")', 'active', datetime('now'), datetime('now'))
	       ON CONFLICT(mac) DO UPDATE SET last_seen=datetime('now'), updated_at=datetime('now');"
}

db_usage_get() {
	acct="$1"; period_start="$2"
	_valid_int "$acct" || return 1
	_sql "SELECT seconds_used, bytes_up, bytes_down FROM usage_periods
	       WHERE account_id=$acct AND period_start='$(_sql_escape "$period_start")' LIMIT 1;"
}

db_profile_get() {
	id="$1"; _valid_int "$id" || return 1
	_sql "SELECT period_type, time_limit_s, upload_limit_b, download_limit_b,
	              upload_rate_kbps, download_rate_kbps, max_devices
	       FROM profiles WHERE id=$id LIMIT 1;"
}

# Consume a short-lived FAS transaction and establish one active session in a
# single SQLite transaction. Output is:
# account_id<TAB>device_id<TAB>policy_snapshot<TAB>auth_key
#
# The temporary table keeps the selected row inside the same sqlite3 process;
# this is important because auth admission and active-session creation must not
# be split into independent commands.
db_auth_consume() {
	auth_key="$1"; mac="$2"; session_start="$3"
	_valid_hex32 "$auth_key" || return 1
	_valid_mac "$mac" || return 1
	_valid_epoch "$session_start" || return 1

result=$(sqlite3 -cmd '.timeout 5000' -batch -separator '|' "$DB_PATH" <<SQL
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
CREATE TEMP TABLE oh_auth_context (
    auth_key TEXT, account_id INTEGER, device_mac TEXT,
    policy_snapshot TEXT, profile_id INTEGER
);
INSERT INTO oh_auth_context(auth_key, account_id, device_mac, policy_snapshot, profile_id)
SELECT t.auth_key, t.account_id, t.device_mac, t.policy_snapshot, t.profile_id
  FROM auth_transactions t
  JOIN accounts a ON a.id = t.account_id
  JOIN profiles p ON p.id = t.profile_id
 WHERE t.auth_key = '$(_sql_escape "$auth_key")'
   AND t.device_mac = '$mac'
   AND t.state = 'pending'
   AND julianday(t.expires_at) > julianday('now')
   AND a.status = 'active'
   AND a.deleted_at IS NULL
   AND (a.expires_at IS NULL OR julianday(a.expires_at) > julianday('now'))
   AND NOT EXISTS (
       SELECT 1 FROM devices blocked
        WHERE blocked.mac = t.device_mac
          AND (blocked.account_id != t.account_id OR blocked.status = 'blocked')
   )
   AND (
       SELECT count(*)
         FROM active_sessions live
         JOIN devices live_device ON live_device.id = live.device_id
        WHERE live.account_id = t.account_id
          AND live.state = 'active'
          AND live_device.mac != t.device_mac
   ) < p.max_devices;
UPDATE auth_transactions
   SET state = 'consumed', consumed_at = datetime('now')
 WHERE auth_key IN (SELECT auth_key FROM oh_auth_context);
INSERT INTO devices(account_id, mac, status, last_seen, updated_at)
SELECT account_id, device_mac, 'active', datetime('now'), datetime('now')
  FROM oh_auth_context
 WHERE 1
ON CONFLICT(mac) DO UPDATE SET
    last_seen = datetime('now'), updated_at = datetime('now');
UPDATE active_sessions
   SET state = 'closed', closed_at = datetime('now'), last_seen_at = datetime('now')
 WHERE state = 'active'
   AND device_id IN (
       SELECT d.id FROM devices d JOIN oh_auth_context c ON c.device_mac = d.mac
   );
INSERT INTO active_sessions(account_id, device_id, session_key,
                            started_at, last_seen_at, state)
SELECT c.account_id, d.id, c.auth_key,
       datetime($session_start, 'unixepoch'), datetime('now'), 'active'
  FROM oh_auth_context c
  JOIN devices d ON d.mac = c.device_mac AND d.account_id = c.account_id;
SELECT c.account_id || char(9) || d.id || char(9) || c.policy_snapshot || char(9) || c.auth_key
  FROM oh_auth_context c
  JOIN devices d ON d.mac = c.device_mac AND d.account_id = c.account_id;
COMMIT;
SQL
	) || return 1
	[ -n "$result" ] || return 1
	printf '%s\n' "$result"
}

db_session_period_type() {
	session_key="$1"; mac="$2"
	_valid_hex32 "$session_key" || return 1
	_valid_mac "$mac" || return 1
	_sql "SELECT p.period_type
	         FROM active_sessions s
         JOIN devices d ON d.id = s.device_id
         JOIN accounts a ON a.id = s.account_id
         JOIN profiles p ON p.id = a.profile_id
        WHERE s.session_key = '$(_sql_escape "$session_key")'
          AND s.state = 'active' AND d.mac = '$mac' LIMIT 1;"
}

# db_session_close <method> <mac> <session_key> <incoming> <outgoing>
#     <session_start> <session_end> <segments>
#
# Incoming is the openNDS download counter and outgoing is the upload counter.
# segments contains one validated row per period:
# period_start|period_end|seconds|upload_bytes|download_bytes
# The raw event and all period aggregates are committed atomically and the
# event key makes repeated callbacks harmless.
db_session_close() {
	method="$1"; mac="$2"; session_key="$3"; incoming="$4"; outgoing="$5"
	session_start="$6"; session_end="$7"; segments="$8"
	_valid_ident "$method" || return 1
	_valid_mac "$mac" || return 1
	_valid_hex32 "$session_key" || return 1
	_valid_int "$incoming" || return 1
	_valid_int "$outgoing" || return 1
	_valid_epoch "$session_start" || return 1
	_valid_epoch "$session_end" || return 1
	[ "$session_end" -ge "$session_start" ] || return 1
	[ -n "$segments" ] || return 1

	event_key="${session_key}:${session_start}:${session_end}"
	sql="PRAGMA busy_timeout=5000;
BEGIN IMMEDIATE;
	CREATE TEMP TABLE oh_close_context(session_id INTEGER, account_id INTEGER, device_id INTEGER);
	INSERT INTO oh_close_context(session_id, account_id, device_id)
SELECT s.id, s.account_id, s.device_id
  FROM active_sessions s JOIN devices d ON d.id = s.device_id
 WHERE s.session_key = '$(_sql_escape "$session_key")'
   AND s.state = 'active' AND d.mac = '$mac';
INSERT OR IGNORE INTO usage_events
    (event_key, account_id, device_id, method, mac, bytes_incoming,
     bytes_outgoing, session_start, session_end)
SELECT '$(_sql_escape "$event_key")', c.account_id, c.device_id,
       '$method', '$mac', $incoming, $outgoing, '$session_start', '$session_end'
  FROM oh_close_context c;
CREATE TEMP TABLE oh_event_flag AS SELECT changes() AS inserted;
"

	segment_count=0
	old_ifs="$IFS"
	IFS='|'
	while read -r period_start period_end add_seconds add_up add_down; do
		[ -n "$period_start" ] || continue
		case "$period_start:$period_end" in *[!0-9TZ:.-]*) return 1 ;; esac
		_valid_int "$add_seconds" && _valid_int "$add_up" && _valid_int "$add_down" || return 1
		segment_count=$((segment_count + 1))
		sql="$sql
INSERT INTO usage_periods
    (account_id, period_start, period_end, seconds_used, bytes_up, bytes_down)
SELECT c.account_id, '$(_sql_escape "$period_start")', '$(_sql_escape "$period_end")',
       $add_seconds, $add_up, $add_down
  FROM oh_close_context c, oh_event_flag f
 WHERE f.inserted = 1
ON CONFLICT(account_id, period_start) DO UPDATE SET
    seconds_used = seconds_used + excluded.seconds_used,
    bytes_up = bytes_up + excluded.bytes_up,
    bytes_down = bytes_down + excluded.bytes_down;
"
	done <<EOF
$segments
EOF
	IFS="$old_ifs"
	[ "$segment_count" -gt 0 ] || return 1

	sql="$sql
UPDATE active_sessions
   SET state = 'closed', closed_at = datetime('now'), last_seen_at = datetime('now')
 WHERE id IN (SELECT session_id FROM oh_close_context)
   AND state = 'active';
UPDATE devices SET last_seen = datetime('now'), updated_at = datetime('now')
 WHERE id IN (SELECT device_id FROM oh_close_context);
SELECT (SELECT count(*) FROM oh_close_context) || '|' ||
       (SELECT inserted FROM oh_event_flag);
COMMIT;"
	result=$(sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" "$sql") || return 1
	[ "$result" = '1|1' ] || return 1
}

# Insert the raw event and accrue only when this event_key was new. The
# transaction makes the deduplication gate and aggregate update indivisible.
db_usage_accrue_if_new() {
	device_id="$1"; session_start="$2"; session_end="$3"; method="$4"
	account_id="$5"; period_start="$6"; period_end="$7"
	add_seconds="$8"; add_up="$9"; add_down="${10}"; mac="${11:-00:00:00:00:00:00}"

	_valid_int "$device_id" || return 1
	_valid_int "$account_id" || return 1
	_valid_epoch "$session_start" || return 1
	_valid_epoch "$session_end" || return 1
	_valid_ident "$method" || return 1
	_valid_int "$add_seconds" && _valid_int "$add_up" && _valid_int "$add_down" || return 1
	_valid_mac "$mac" || return 1

	event_key="${device_id}:${session_start}:${session_end}"
	sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" <<SQL
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO usage_events
    (event_key, account_id, device_id, method, mac, bytes_incoming,
     bytes_outgoing, session_start, session_end)
VALUES ('$(_sql_escape "$event_key")', $account_id, $device_id,
        '$method', '$mac', $add_down, $add_up, '$session_start', '$session_end');
INSERT INTO usage_periods
    (account_id, period_start, period_end, seconds_used, bytes_up, bytes_down)
SELECT $account_id, '$(_sql_escape "$period_start")', '$(_sql_escape "$period_end")',
       $add_seconds, $add_up, $add_down
WHERE changes() = 1
ON CONFLICT(account_id, period_start) DO UPDATE SET
    seconds_used=seconds_used + excluded.seconds_used,
    bytes_up=bytes_up + excluded.bytes_up,
    bytes_down=bytes_down + excluded.bytes_down;
UPDATE devices SET last_seen=datetime('now'), updated_at=datetime('now') WHERE id=$device_id;
COMMIT;
SQL
}

# Conditional UPDATE is the concurrency guard; BEGIN IMMEDIATE serializes the
# state transition with account creation/redemption work on the same DB.
db_voucher_redeem() {
	code="$1"; account_id="$2"
	_valid_ident "$code" || return 1
	_valid_int "$account_id" || return 1
	changes=$(sqlite3 -cmd '.timeout 5000' -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE vouchers SET status='redeemed', redeemed_by=$account_id, redeemed_at=datetime('now')
	 WHERE code='$(_sql_escape "$code")' AND status='unused';
	SELECT changes(); COMMIT;" | tail -n 1)
	[ "$changes" = "1" ]
}

db_log_event() {
	action="$1"; account_id="$2"; detail="$3"
	_valid_ident "$action" || return 1
	acct_sql='NULL'; _valid_int "$account_id" && acct_sql="$account_id"
	_sql "INSERT INTO admin_events(account_id, action, detail)
	       VALUES ($acct_sql, '$action', '$(_sql_escape "$detail")');"
}
