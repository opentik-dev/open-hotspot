#!/bin/sh
set -eu

# Controlled account-switching contract. This is deliberately a SQLite/domain
# test: it proves transaction ordering and redaction, not native openNDS
# enforcement. The latter remains a physical-router gate.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/oh-switch.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
DB="$TMP/hotspot.db"
export OPEN_HOTSPOT_DB_PATH="$DB" DB_PATH="$DB"
export OPEN_HOTSPOT_SCHEMA_PATH="$ROOT/starter-kit/root/usr/lib/open-hotspot/schema.sql"
export OPEN_HOTSPOT_MIGRATIONS_PATH="$ROOT/starter-kit/root/usr/lib/open-hotspot/migrations"
. "$ROOT/starter-kit/root/usr/lib/open-hotspot/db.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }
expect() {
	name="$1"; expected_rc="$2"; expected_text="$3"; shift 3
	set +e
	output=$($@ 2>/dev/null); rc=$?
	set -e
	if [ "$rc" = "$expected_rc" ] && printf '%s\n' "$output" | grep -F "$expected_text" >/dev/null; then
		pass "$name"
	else
		fail "$name (rc=$rc output=$output expected rc=$expected_rc text=$expected_text)"
	fi
}

reset_db() {
	rm -f "$DB" "$DB-wal" "$DB-shm"
	sqlite3 "$DB" < "$OPEN_HOTSPOT_SCHEMA_PATH" >/dev/null
	sqlite3 "$DB" <<'SQL'
INSERT INTO profiles(id,name,period_type,time_limit_s,upload_limit_b,download_limit_b,upload_rate_kbps,download_rate_kbps,max_devices)
VALUES (2,'target','none',3600,2000,2000,300,400,1),
       (3,'old','none',3600,1000,1000,100,200,1);
INSERT INTO accounts(id,username,pin_hash,pin_salt,pin_iter,profile_id,status)
VALUES (1,'old','h','s',1,3,'suspended'),
       (2,'target','h','s',1,2,'active');
SQL
}

snapshot='2|3600|2000|2000|300|400|1970-01-01T00:00:00Z|2038-01-19T03:14:07Z'
add_auth() {
	key="$1"; mac="$2"; account="${3:-2}"
	sqlite3 "$DB" "INSERT INTO auth_transactions(auth_key,account_id,device_mac,profile_id,policy_snapshot,expires_at,state) VALUES ('$key',$account,'$mac',2,'$snapshot',datetime('now','+15 minutes'),'pending');"
}
consume() { db_auth_consume "$1" "$2" "$(date -u +%s)"; }

# 1. New device.
reset_db; add_auth 00000000000000000000000000000001 AA:00:00:00:00:01
expect 'fresh device admission' 0 '00000000000000000000000000000001' consume 00000000000000000000000000000001 AA:00:00:00:00:01

# 2-7. Previous ownership is eligible after expiry, suspension, deletion, or
# exhaustion of any aggregate dimension.
for item in expired suspended deleted time up down; do
	reset_db
	case "$item" in
		expired) sqlite3 "$DB" "UPDATE accounts SET status='active',expires_at='2000-01-01T00:00:00Z' WHERE id=1;" ;;
		suspended) : ;;
		deleted) sqlite3 "$DB" "UPDATE accounts SET status='active',deleted_at=datetime('now') WHERE id=1;" ;;
		time) sqlite3 "$DB" "UPDATE accounts SET status='active'; INSERT INTO usage_periods(account_id,period_start,period_end,seconds_used) VALUES (1,'1970-01-01T00:00:00Z','2038-01-19T03:14:07Z',3600);" ;;
		up) sqlite3 "$DB" "UPDATE accounts SET status='active'; INSERT INTO usage_periods(account_id,period_start,period_end,bytes_up) VALUES (1,'1970-01-01T00:00:00Z','2038-01-19T03:14:07Z',1000);" ;;
		down) sqlite3 "$DB" "UPDATE accounts SET status='active'; INSERT INTO usage_periods(account_id,period_start,period_end,bytes_down) VALUES (1,'1970-01-01T00:00:00Z','2038-01-19T03:14:07Z',1000);" ;;
	esac
	key="0000000000000000000000000000000${item#?}"
	# Keep keys hexadecimal and unique per case.
	key=$(printf '%032x' "$((10 + ${#item}))")
	mac="AA:00:00:00:00:$(printf '%02X' ${#item})"
	add_auth "$key" "$mac"
	expect "switch allowed: previous account $item" 0 "$key" consume "$key" "$mac"
done

# 8. An active, unexpired previous account with remaining quota is protected.
reset_db; sqlite3 "$DB" "UPDATE accounts SET status='active' WHERE id=1;"; sqlite3 "$DB" "INSERT INTO devices(account_id,mac,status) VALUES (1,'AA:00:00:00:00:08','active');"; add_auth 00000000000000000000000000000008 AA:00:00:00:00:08
expect 'active previous account is rejected' 1 'previous-account-active' consume 00000000000000000000000000000008 AA:00:00:00:00:08

# 9-10. Both live and pending sessions block a switch.
for state in active pending; do
	reset_db; sqlite3 "$DB" "UPDATE accounts SET status='active' WHERE id=1; INSERT INTO devices(id,account_id,mac,status) VALUES (10,1,'AA:00:00:00:00:09','$([ "$state" = blocked ] && printf blocked || printf active)'); INSERT INTO active_sessions(account_id,device_id,session_key,started_at,last_seen_at,state) VALUES (1,10,'99999999999999999999999999999999',datetime('now'),datetime('now'),'$state');"
	key="0000000000000000000000000000001${#state}"; add_auth "$key" AA:00:00:00:00:09
	expect "${state} session blocks switch" 1 'live-session' consume "$key" AA:00:00:00:00:09
done

# 11. Blocked device.
reset_db; sqlite3 "$DB" "INSERT INTO devices(account_id,mac,status) VALUES (1,'AA:00:00:00:00:11','blocked');"; add_auth 00000000000000000000000000000011 AA:00:00:00:00:11
expect 'blocked device is rejected' 1 'device-blocked' consume 00000000000000000000000000000011 AA:00:00:00:00:11

# 12. Target max-devices counts active/pending distinct devices.
reset_db; sqlite3 "$DB" "INSERT INTO devices(id,account_id,mac,status) VALUES (20,2,'AA:00:00:00:00:20','active'); INSERT INTO active_sessions(account_id,device_id,session_key,started_at,last_seen_at,state) VALUES (2,20,'22222222222222222222222222222222',datetime('now'),datetime('now'),'active');"; add_auth 00000000000000000000000000000012 AA:00:00:00:00:12
expect 'target max devices is enforced' 1 'max-devices-exceeded' consume 00000000000000000000000000000012 AA:00:00:00:00:12

# 13. Snapshot/rate/remaining mismatch is stale-policy.
reset_db; sqlite3 "$DB" "UPDATE profiles SET download_rate_kbps=999 WHERE id=2;"; add_auth 00000000000000000000000000000013 AA:00:00:00:00:13
expect 'changed policy snapshot is rejected' 1 'stale-policy' consume 00000000000000000000000000000013 AA:00:00:00:00:13

# 14. Historical events keep the old account and device after a switch.
reset_db; sqlite3 "$DB" "INSERT INTO devices(id,account_id,mac,status) VALUES (14,1,'AA:00:00:00:00:14','active'); INSERT INTO usage_events(event_key,account_id,device_id,method,mac,session_start,session_end) VALUES ('old-event',1,14,'client_deauth','AA:00:00:00:00:14','100','160');"; add_auth 00000000000000000000000000000014 AA:00:00:00:00:14
expect 'historical accounting survives switch' 0 '00000000000000000000000000000014' consume 00000000000000000000000000000014 AA:00:00:00:00:14
[ "$(sqlite3 "$DB" "SELECT account_id||':'||device_id FROM usage_events WHERE event_key='old-event';")" = '1:14' ] && pass 'old account/device remain in usage history' || fail 'old account/device history changed'

# 15-16. A consumed transaction retries idempotently while active, then
# refuses the same key after its session is closed.
reset_db; add_auth 00000000000000000000000000000015 AA:00:00:00:00:15
expect 'active consumed retry is idempotent' 0 '00000000000000000000000000000015' consume 00000000000000000000000000000015 AA:00:00:00:00:15
expect 'second active retry returns same session' 0 '00000000000000000000000000000015' consume 00000000000000000000000000000015 AA:00:00:00:00:15
[ "$(sqlite3 "$DB" 'SELECT count(*) FROM active_sessions;')" = 1 ] && pass 'active retry does not duplicate session' || fail 'active retry duplicated session'
sqlite3 "$DB" "UPDATE active_sessions SET state='closed',closed_at=datetime('now');"
expect 'closed consumed transaction is not replayed' 1 'already-consumed' consume 00000000000000000000000000000015 AA:00:00:00:00:15

# 17. MAC mismatch rejects the pending transaction.
reset_db; add_auth 00000000000000000000000000000017 AA:00:00:00:00:17
expect 'MAC mismatch is auth-invalid' 1 'auth-invalid' consume 00000000000000000000000000000017 AA:00:00:00:00:99

# 18. Denial retry returns the stored reason without a second audit event.
reset_db; sqlite3 "$DB" "UPDATE accounts SET status='active' WHERE id=1; INSERT INTO devices(account_id,mac,status) VALUES (1,'AA:00:00:00:00:18','active');"; add_auth 00000000000000000000000000000018 AA:00:00:00:00:18
first=$(consume 00000000000000000000000000000018 AA:00:00:00:00:18 || true); second=$(consume 00000000000000000000000000000018 AA:00:00:00:00:18 || true)
[ "$first" = "$second" ] && [ "$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_switch_denied';")" = 1 ] && pass 'denial retry is idempotent and preserves reason' || fail 'denial retry duplicated or changed reason'

# 19. A unique-session insertion failure rolls back ownership, auth state, and audit.
reset_db; sqlite3 "$DB" "INSERT INTO devices(id,account_id,mac,status) VALUES (19,1,'AA:00:00:00:00:19','active'); INSERT INTO active_sessions(account_id,device_id,session_key,started_at,last_seen_at,state) VALUES (2,19,'00000000000000000000000000000019',datetime('now'),datetime('now'),'closed');"; add_auth 00000000000000000000000000000019 AA:00:00:00:00:19
expect 'session insertion failure rolls back' 1 'database' consume 00000000000000000000000000000019 AA:00:00:00:00:19
[ "$(sqlite3 "$DB" "SELECT account_id FROM devices WHERE id=19;")" = 1 ] && [ "$(sqlite3 "$DB" "SELECT state FROM auth_transactions WHERE auth_key='00000000000000000000000000000019';")" = pending ] && [ "$(sqlite3 "$DB" "SELECT count(*) FROM admin_events;")" = 0 ] && pass 'rollback preserved ownership, pending auth, and audit' || fail 'rollback mutated state'

# 20. Two competing switches serialize: one winner, one denial, one session.
reset_db; sqlite3 "$DB" "INSERT INTO accounts(id,username,pin_hash,pin_salt,pin_iter,profile_id,status) VALUES (3,'target2','h','s',1,2,'active');"; add_auth 00000000000000000000000000000020 AA:00:00:00:00:20 2; add_auth 00000000000000000000000000000021 AA:00:00:00:00:20 3
(consume 00000000000000000000000000000020 AA:00:00:00:00:20 >/dev/null 2>&1 || true) & p1=$!
(consume 00000000000000000000000000000021 AA:00:00:00:00:20 >/dev/null 2>&1 || true) & p2=$!
wait "$p1"; wait "$p2"
[ "$(sqlite3 "$DB" "SELECT count(*) FROM active_sessions WHERE state='active';")" = 1 ] && [ "$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE mac='AA:00:00:00:00:20';")" = 1 ] && pass 'competing switches have one winner' || fail 'competing switches produced inconsistent state'

# 21. Audit details are redacted and unknown devices use a safe fallback.
reset_db; sqlite3 "$DB" "UPDATE accounts SET status='suspended' WHERE id=2;"; add_auth 00000000000000000000000000000021 AA:00:00:00:00:21
consume 00000000000000000000000000000021 AA:00:00:00:00:21 >/dev/null 2>&1 || true
details=$(sqlite3 "$DB" "SELECT action||':'||detail FROM admin_events;")
if printf '%s' "$details" | grep -F 'device_id=unknown' >/dev/null && ! printf '%s' "$details" | grep -Eiq 'aa:00|pin|token|192\.168'; then
	pass 'audit events contain no raw MAC, IP, PIN, or token'
else
	fail 'audit fallback or redaction contract failed'
fi

if [ "$FAIL" -eq 0 ]; then
	printf 'test_account_switch: %s passed, %s failed\n' "$PASS" "$FAIL"
	exit 0
fi
printf 'test_account_switch: %s passed, %s failed\n' "$PASS" "$FAIL" >&2
exit 1
