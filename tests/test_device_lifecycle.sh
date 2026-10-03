#!/bin/sh
set -eu

# test_device_lifecycle.sh — Comprehensive tests for device removal lifecycle and failure observability:
# 1. Device removal with invalid ID fails closed and logs device_remove_denied with reason=invalid-id
# 2. Device removal for non-existent ID fails with device-not-found and logs device_remove_denied
# 3. Device removal with active live session fails with live-session and logs device_remove_denied
# 4. Device removal with pending live session fails with live-session and logs device_remove_denied
# 5. Device removal with historical usage_events fails with usage-history and logs device_remove_denied
# 6. Device removal with closed active_sessions fails with usage-history and logs device_remove_denied
# 7. Device removal with no history succeeds, deletes device, and logs device_removed
# 8. rpcd device_remove returns exact machine-readable reasons over ubus/JSON
# 9. No raw MAC addresses, IPs, PINs, keys, or tokens leak into admin_events details or RPC output
# 10. LuCI controller and views provide actionable human explanations

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TMP_DIR=$(mktemp -d /tmp/oh-dev-lifecycle.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

ADMIN="$PROJECT/starter-kit/root/usr/lib/open-hotspot/admin.sh"
RPC="$PROJECT/starter-kit/root/usr/libexec/rpcd/open_hotspot"
CONTROLLER="$PROJECT/starter-kit/luasrc/controller/open-hotspot.lua"
VIEW="$PROJECT/starter-kit/luasrc/view/open-hotspot/devices.htm"
SCHEMA="$PROJECT/starter-kit/root/usr/lib/open-hotspot/schema.sql"
DB="$TMP_DIR/hotspot.db"

export OPEN_HOTSPOT_DB_PATH="$DB"
export OPEN_HOTSPOT_SCHEMA_PATH="$SCHEMA"
export OPEN_HOTSPOT_DB_HELPER="$PROJECT/starter-kit/root/usr/lib/open-hotspot/db.sh"
export OPEN_HOTSPOT_PBKDF2_HELPER_SH="$PROJECT/starter-kit/root/usr/lib/open-hotspot/pbkdf2.sh"
export OPEN_HOTSPOT_ADMIN_BIN="$ADMIN"

MOCK_NDS="$TMP_DIR/mock-nds.sh"
cat << 'EOF' > "$MOCK_NDS"
#!/bin/sh
if [ "${1:-}" = "deauth" ]; then
	printf '%s\n' "${2:-}" >> "$OPEN_HOTSPOT_DEAUTH_LOG"
	exit 0
fi
exit 0
EOF
chmod +x "$MOCK_NDS"
export OPEN_HOTSPOT_NDS_HELPER="$MOCK_NDS"
export OPEN_HOTSPOT_DEAUTH_LOG="$TMP_DIR/deauth.log"
touch "$OPEN_HOTSPOT_DEAUTH_LOG"

if [ ! -f /usr/share/libubox/jshn.sh ]; then
	export OPEN_HOTSPOT_JSHN_SH="$PROJECT/tests/fixtures/mock-jshn.sh"
fi

PASSES=0
FAILURES=0

pass() { PASSES=$((PASSES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# Initialize clean database schema
sqlite3 "$DB" < "$SCHEMA" >/dev/null

# Seed test accounts (profile 1 is seeded by schema.sql)
sqlite3 "$DB" <<SQL
INSERT INTO accounts(id, username, profile_id, pin_hash, pin_salt, pin_iter, status)
VALUES (1, 'alice', 1, 'mockhash1', 'mocksalt1', 1000, 'active');

INSERT INTO accounts(id, username, profile_id, pin_hash, pin_salt, pin_iter, status)
VALUES (2, 'bob', 1, 'mockhash2', 'mocksalt2', 1000, 'active');
SQL

# ==============================================================================
# 1. Invalid Device ID
# ==============================================================================
out=$( "$ADMIN" device-remove "not-an-id" 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "invalid-id" ]; then
	pass "admin.sh device-remove rejects invalid non-numeric ID with invalid-id"
else
	fail "admin.sh device-remove invalid ID returned rc=$rc output='$out'"
fi

evt_invalid=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND detail='reason=invalid-id';")
if [ "$evt_invalid" -eq 1 ]; then
	pass "admin.sh logged device_remove_denied event for invalid ID"
else
	fail "admin.sh did not log device_remove_denied for invalid ID"
fi

# ==============================================================================
# 2. Non-existent Device
# ==============================================================================
out=$( "$ADMIN" device-remove 9999 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "device-not-found" ]; then
	pass "admin.sh device-remove returns device-not-found for missing device"
else
	fail "admin.sh device-remove missing device returned rc=$rc output='$out'"
fi

evt_notfound=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND detail='reason=device-not-found:device_id=9999';")
if [ "$evt_notfound" -eq 1 ]; then
	pass "admin.sh logged device_remove_denied event for device-not-found"
else
	fail "admin.sh did not log device_remove_denied for device-not-found"
fi

# ==============================================================================
# 3. Device with Live Active Session
# ==============================================================================
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (10, 1, '00:11:22:33:44:01', 'active');
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state)
VALUES (100, 1, 10, 'sess-live-active-01', datetime('now'), datetime('now'), 'active');
SQL

out=$( "$ADMIN" device-remove 10 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "live-session" ]; then
	pass "admin.sh device-remove rejects device with active session with live-session"
else
	fail "admin.sh device-remove with active session returned rc=$rc output='$out'"
fi

dev10_exists=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=10;")
if [ "$dev10_exists" -eq 1 ]; then
	pass "Device with active session was not deleted from database"
else
	fail "Device with active session was incorrectly deleted"
fi

evt_live=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND account_id=1 AND detail='reason=live-session:device_id=10';")
if [ "$evt_live" -eq 1 ]; then
	pass "admin.sh logged device_remove_denied for live-session with account_id and device_id"
else
	fail "admin.sh did not log device_remove_denied for live-session"
fi

# ==============================================================================
# 4. Device with Pending Session
# ==============================================================================
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (11, 1, '00:11:22:33:44:02', 'active');
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state)
VALUES (101, 1, 11, 'sess-live-pending-02', datetime('now'), datetime('now'), 'pending');
SQL

out=$( "$ADMIN" device-remove 11 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "live-session" ]; then
	pass "admin.sh device-remove rejects device with pending session with live-session"
else
	fail "admin.sh device-remove with pending session returned rc=$rc output='$out'"
fi

dev11_exists=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=11;")
if [ "$dev11_exists" -eq 1 ]; then
	pass "Device with pending session was not deleted from database"
else
	fail "Device with pending session was incorrectly deleted"
fi

# ==============================================================================
# 5. Device with Usage Events (Historical Accounting)
# ==============================================================================
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (12, 1, '00:11:22:33:44:03', 'active');
INSERT INTO usage_events(id, event_key, account_id, device_id, method, mac, bytes_incoming, bytes_outgoing, session_start, session_end)
VALUES (200, 'evt-hist-01', 1, 12, 'auth_close', '00:11:22:33:44:03', 4096, 8192, datetime('now'), datetime('now'));
SQL

out=$( "$ADMIN" device-remove 12 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "usage-history" ]; then
	pass "admin.sh device-remove rejects device with usage events with usage-history"
else
	fail "admin.sh device-remove with usage events returned rc=$rc output='$out'"
fi

dev12_exists=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=12;")
if [ "$dev12_exists" -eq 1 ]; then
	pass "Device with historical usage was not deleted from database"
else
	fail "Device with historical usage was incorrectly deleted"
fi

evt_hist=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND account_id=1 AND detail='reason=usage-history:device_id=12';")
if [ "$evt_hist" -eq 1 ]; then
	pass "admin.sh logged device_remove_denied for usage-history with account_id and device_id"
else
	fail "admin.sh did not log device_remove_denied for usage-history"
fi

# ==============================================================================
# 6. Device with Closed Active Session Record (Foreign Key Protection)
# ==============================================================================
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (13, 1, '00:11:22:33:44:04', 'active');
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state, closed_at)
VALUES (103, 1, 13, 'sess-closed-03', datetime('now'), datetime('now'), 'closed', datetime('now'));
SQL

out=$( "$ADMIN" device-remove 13 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "usage-history" ]; then
	pass "admin.sh device-remove rejects device with closed session record with usage-history"
else
	fail "admin.sh device-remove with closed session returned rc=$rc output='$out'"
fi

dev13_exists=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=13;")
if [ "$dev13_exists" -eq 1 ]; then
	pass "Device with closed session was not deleted (foreign key protection maintained)"
else
	fail "Device with closed session was incorrectly deleted"
fi

# ==============================================================================
# 7. Device with No History Succeeds
# ==============================================================================
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (14, 2, '00:11:22:33:44:05', 'active');
SQL

out=$( "$ADMIN" device-remove 14 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
	pass "admin.sh device-remove on history-free device succeeded with exit code 0"
else
	fail "admin.sh device-remove on clean device failed with rc=$rc output='$out'"
fi

dev14_exists=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=14;")
if [ "$dev14_exists" -eq 0 ]; then
	pass "Clean device 14 was successfully removed from database"
else
	fail "Clean device 14 was not removed from database"
fi

evt_removed=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_removed' AND account_id=2 AND detail='device_id=14';")
if [ "$evt_removed" -eq 1 ]; then
	pass "admin.sh logged device_removed event with account_id and device_id"
else
	fail "admin.sh did not log device_removed event"
fi

# ==============================================================================
# 8. RPC Boundary Machine-Readable Error Responses
# ==============================================================================
# Invalid ID over RPC
res_invalid=$(printf '{"id":"xyz"}' | "$RPC" call device_remove 2>&1 || true)
if printf '%s' "$res_invalid" | grep -F '"ok": false' >/dev/null && \
   printf '%s' "$res_invalid" | grep -F '"error": "invalid-id"' >/dev/null; then
	pass "RPC device_remove propagates error 'invalid-id'"
else
	fail "RPC device_remove invalid-id response incorrect: $res_invalid"
fi

# Missing device over RPC
res_missing=$(printf '{"id":7777}' | "$RPC" call device_remove 2>&1 || true)
if printf '%s' "$res_missing" | grep -F '"ok": false' >/dev/null && \
   printf '%s' "$res_missing" | grep -F '"error": "device-not-found"' >/dev/null; then
	pass "RPC device_remove propagates error 'device-not-found'"
else
	fail "RPC device_remove device-not-found response incorrect: $res_missing"
fi

# Live session over RPC (device 10)
res_live=$(printf '{"id":10}' | "$RPC" call device_remove 2>&1 || true)
if printf '%s' "$res_live" | grep -F '"ok": false' >/dev/null && \
   printf '%s' "$res_live" | grep -F '"error": "live-session"' >/dev/null; then
	pass "RPC device_remove propagates error 'live-session'"
else
	fail "RPC device_remove live-session response incorrect: $res_live"
fi

# Usage history over RPC (device 12)
res_hist=$(printf '{"id":12}' | "$RPC" call device_remove 2>&1 || true)
if printf '%s' "$res_hist" | grep -F '"ok": false' >/dev/null && \
   printf '%s' "$res_hist" | grep -F '"error": "usage-history"' >/dev/null; then
	pass "RPC device_remove propagates error 'usage-history'"
else
	fail "RPC device_remove usage-history response incorrect: $res_hist"
fi

# Clean device over RPC
sqlite3 "$DB" "INSERT INTO devices(id, account_id, mac, status) VALUES (15, 2, '00:11:22:33:44:06', 'active');"
res_clean=$(printf '{"id":15}' | "$RPC" call device_remove 2>&1)
if printf '%s' "$res_clean" | grep -F '"ok": true' >/dev/null; then
	pass "RPC device_remove succeeds for clean device"
else
	fail "RPC device_remove clean device response incorrect: $res_clean"
fi

dev15_exists=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=15;")
if [ "$dev15_exists" -eq 0 ]; then
	pass "RPC clean device 15 was deleted from database"
else
	fail "RPC clean device 15 was not deleted from database"
fi

# ==============================================================================
# 9. No Sensitive Data in Event Details or UI Output
# ==============================================================================
# Inspect all logged events for device removal
leaked_macs=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action IN ('device_removed', 'device_remove_denied') AND (detail LIKE '%00:11:%' OR detail LIKE '%00-11-%');")
if [ "$leaked_macs" -eq 0 ]; then
	pass "No raw MAC addresses were leaked in admin_events details"
else
	fail "Found $leaked_macs raw MAC addresses leaked in admin_events details"
fi

leaked_ip_pin=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action IN ('device_removed', 'device_remove_denied') AND (detail LIKE '%192.168%' OR detail LIKE '%pin=%' OR detail LIKE '%token=%');")
if [ "$leaked_ip_pin" -eq 0 ]; then
	pass "No IPs, PINs, or tokens were leaked in admin_events details"
else
	fail "Found $leaked_ip_pin sensitive fields in admin_events details"
fi

# Check RPC dev_events_list output for these events
events_rpc_out=$(printf '{}' | "$RPC" call dev_events_list)
if printf '%s' "$events_rpc_out" | grep -F '00:11:22:33:44' >/dev/null; then
	fail "RPC dev_events_list leaked raw MAC address"
else
	pass "RPC dev_events_list output contains zero unredacted MAC addresses"
fi

# ==============================================================================
# 10. Device List Lifecycle Indicators & Precedence (CLI)
# ==============================================================================
# Device 50 has both closed session (history) AND active session (live)
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (50, 1, '00:11:22:33:44:50', 'active');
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state, closed_at)
VALUES (501, 1, 50, 'sess-closed-50', datetime('now'), datetime('now'), 'closed', datetime('now'));
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state)
VALUES (502, 1, 50, 'sess-active-50', datetime('now'), datetime('now'), 'active');
SQL

# Clean device 60 has no sessions and no usage events
sqlite3 "$DB" "INSERT INTO devices(id, account_id, mac, status) VALUES (60, 2, '00:11:22:33:44:60', 'active');"

dev_list_out=$("$ADMIN" device-list)

# Check device 50: has_history must be 1, lifecycle_state must be 'live' (precedence: live > historical > removable)
d50_line=$(printf '%s\n' "$dev_list_out" | grep '^50|' || true)
if [ -n "$d50_line" ]; then
	d50_hist=$(printf '%s' "$d50_line" | awk -F'|' '{print $9}')
	d50_state=$(printf '%s' "$d50_line" | awk -F'|' '{print $10}')
	if [ "$d50_hist" = "1" ] && [ "$d50_state" = "live" ]; then
		pass "admin_device_list reports has_history=1 and lifecycle_state=live for device 50 (precedence live > historical)"
	else
		fail "admin_device_list device 50 mismatch: hist='$d50_hist' state='$d50_state'"
	fi
else
	fail "admin_device_list missing device 50"
fi

# Check device 11: has_history must be 0, lifecycle_state must be 'live', live_sessions must be 1 (pending session)
d11_line=$(printf '%s\n' "$dev_list_out" | grep '^11|' || true)
if [ -n "$d11_line" ]; then
	d11_live=$(printf '%s' "$d11_line" | awk -F'|' '{print $8}')
	d11_hist=$(printf '%s' "$d11_line" | awk -F'|' '{print $9}')
	d11_state=$(printf '%s' "$d11_line" | awk -F'|' '{print $10}')
	if [ "$d11_live" = "1" ] && [ "$d11_hist" = "0" ] && [ "$d11_state" = "live" ]; then
		pass "admin_device_list reports live_sessions=1, has_history=0, lifecycle_state=live for pending device 11"
	else
		fail "admin_device_list device 11 mismatch: live='$d11_live' hist='$d11_hist' state='$d11_state'"
	fi
else
	fail "admin_device_list missing device 11"
fi

# Check device 12: has_history must be 1, lifecycle_state must be 'historical'
d12_line=$(printf '%s\n' "$dev_list_out" | grep '^12|' || true)
if [ -n "$d12_line" ]; then
	d12_hist=$(printf '%s' "$d12_line" | awk -F'|' '{print $9}')
	d12_state=$(printf '%s' "$d12_line" | awk -F'|' '{print $10}')
	if [ "$d12_hist" = "1" ] && [ "$d12_state" = "historical" ]; then
		pass "admin_device_list reports has_history=1 and lifecycle_state=historical for device 12"
	else
		fail "admin_device_list device 12 mismatch: hist='$d12_hist' state='$d12_state'"
	fi
else
	fail "admin_device_list missing device 12"
fi

# Check device 60: has_history must be 0, lifecycle_state must be 'removable'
d60_line=$(printf '%s\n' "$dev_list_out" | grep '^60|' || true)
if [ -n "$d60_line" ]; then
	d60_hist=$(printf '%s' "$d60_line" | awk -F'|' '{print $9}')
	d60_state=$(printf '%s' "$d60_line" | awk -F'|' '{print $10}')
	if [ "$d60_hist" = "0" ] && [ "$d60_state" = "removable" ]; then
		pass "admin_device_list reports has_history=0 and lifecycle_state=removable for clean device 60"
	else
		fail "admin_device_list device 60 mismatch: hist='$d60_hist' state='$d60_state'"
	fi
else
	fail "admin_device_list missing device 60"
fi

# ==============================================================================
# 11. RPC device_list JSON Schema & Type Verification
# ==============================================================================
rpc_dev_json=$(printf '{}' | "$RPC" call device_list)

json_eval_result=$(python3 - <<PYEOF
import json, sys

try:
    data = json.loads('''$rpc_dev_json''')
except Exception as e:
    print(f"JSON_PARSE_ERROR: {e}")
    sys.exit(1)

devices = data.get("devices", [])
if not devices:
    print("EMPTY_DEVICES")
    sys.exit(1)

dev_map = {}
for d in devices:
    d_id = d.get("id")
    has_hist = d.get("has_history")
    l_state = d.get("lifecycle_state")

    # Assert has_history is strictly a JSON boolean, not a string or int
    if not isinstance(has_hist, bool):
        print(f"TYPE_ERROR: device {d_id} has_history is {type(has_hist).__name__}, expected bool")
        sys.exit(1)

    # Assert lifecycle_state is strictly one of the allowed enum values
    if l_state not in ("live", "historical", "removable"):
        print(f"ENUM_ERROR: device {d_id} lifecycle_state is '{l_state}', expected live/historical/removable")
        sys.exit(1)

    dev_map[d_id] = d

# Verify device 50 (live precedence over history)
d50 = dev_map.get(50)
if not d50 or d50["has_history"] is not True or d50["lifecycle_state"] != "live":
    print(f"ASSERTION_FAILED_D50: {d50}")
    sys.exit(1)

# Verify device 11 (pending session: live_sessions=1, lifecycle_state='live', has_history=False)
d11 = dev_map.get(11)
if not d11 or d11["live_sessions"] != 1 or d11["has_history"] is not False or d11["lifecycle_state"] != "live":
    print(f"ASSERTION_FAILED_D11: {d11}")
    sys.exit(1)

# Verify device 12 (historical)
d12 = dev_map.get(12)
if not d12 or d12["has_history"] is not True or d12["lifecycle_state"] != "historical":
    print(f"ASSERTION_FAILED_D12: {d12}")
    sys.exit(1)

# Verify device 60 (removable)
d60 = dev_map.get(60)
if not d60 or d60["has_history"] is not False or d60["lifecycle_state"] != "removable":
    print(f"ASSERTION_FAILED_D60: {d60}")
    sys.exit(1)

print("OK")
PYEOF
)

if [ "$json_eval_result" = "OK" ]; then
	pass "RPC device_list provides valid JSON with boolean has_history and validated lifecycle_state"
else
	fail "RPC device_list JSON type/schema check failed: $json_eval_result"
fi

# ==============================================================================
# 12. Real Automated Controlled Database Failure Test
# ==============================================================================
sqlite3 "$DB" "INSERT INTO devices(id, account_id, mac, status) VALUES (30, 2, '00:11:22:33:44:30', 'active');"
sqlite3 "$DB" <<SQL
CREATE TRIGGER sim_db_failure BEFORE DELETE ON devices
FOR EACH ROW
BEGIN
    SELECT RAISE(FAIL, 'controlled database failure');
END;
SQL

out=$( "$ADMIN" device-remove 30 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "database" ]; then
	pass "admin.sh device-remove returns database error on controlled db failure"
else
	fail "admin.sh device-remove controlled db failure returned rc=$rc output='$out'"
fi

dev30_count=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=30;")
if [ "$dev30_count" -eq 1 ]; then
	pass "Device 30 remains intact in database after controlled database failure"
else
	fail "Device 30 was incorrectly deleted despite database failure"
fi

evt_db_fail=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND account_id=2 AND detail='reason=database:device_id=30';")
if [ "$evt_db_fail" -ge 1 ]; then
	pass "admin.sh logged device_remove_denied with reason=database:device_id=30"
else
	fail "admin.sh did not log device_remove_denied for controlled database failure"
fi

res_rpc_db=$(printf '{"id":30}' | "$RPC" call device_remove 2>&1 || true)
if printf '%s' "$res_rpc_db" | grep -F '"ok": false' >/dev/null && \
   printf '%s' "$res_rpc_db" | grep -F '"error": "database"' >/dev/null; then
	pass "RPC device_remove propagates error 'database' on controlled db failure"
else
	fail "RPC device_remove db failure response incorrect: $res_rpc_db"
fi

sqlite3 "$DB" "DROP TRIGGER sim_db_failure;"

# ==============================================================================
# 13. Concurrency / Race Condition Tests (Simulated Interleaved Session/Usage)
# ==============================================================================
# 13a. Concurrent Session Race
sqlite3 "$DB" "INSERT INTO devices(id, account_id, mac, status) VALUES (40, 2, '00:11:22:33:44:40', 'active');"
sqlite3 "$DB" <<SQL
CREATE TRIGGER sim_race_session BEFORE DELETE ON devices
FOR EACH ROW
BEGIN
    INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state)
    VALUES (400, OLD.account_id, OLD.id, 'sess-race-40', datetime('now'), datetime('now'), 'active');
END;
SQL

out=$( "$ADMIN" device-remove 40 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "database" ]; then
	pass "admin.sh device-remove fails closed when session appears during delete transaction"
else
	fail "admin.sh device-remove race condition returned rc=$rc output='$out'"
fi

dev40_count=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=40;")
if [ "$dev40_count" -eq 1 ]; then
	pass "Concurrent session race: device 40 remained intact in database"
else
	fail "Concurrent session race: device 40 was incorrectly deleted"
fi

sess40_count=$(sqlite3 "$DB" "SELECT count(*) FROM active_sessions WHERE device_id=40;")
if [ "$sess40_count" -eq 0 ]; then
	pass "Concurrent session race: aborted transaction rolled back inserted session"
else
	fail "Concurrent session race: session row was unexpectedly retained"
fi

evt_race_sess=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND account_id=2 AND detail='reason=database:device_id=40';")
if [ "$evt_race_sess" -ge 1 ]; then
	pass "admin.sh logged device_remove_denied for session race condition"
else
	fail "admin.sh did not log device_remove_denied for session race condition"
fi

sqlite3 "$DB" "DROP TRIGGER sim_race_session;"

# 13b. Concurrent Usage Event Race
sqlite3 "$DB" "INSERT INTO devices(id, account_id, mac, status) VALUES (41, 2, '00:11:22:33:44:41', 'active');"
sqlite3 "$DB" <<SQL
CREATE TRIGGER sim_race_usage BEFORE DELETE ON devices
FOR EACH ROW
BEGIN
    INSERT INTO usage_events(id, event_key, account_id, device_id, method, mac, bytes_incoming, bytes_outgoing, session_start, session_end)
    VALUES (401, 'evt-race-41', OLD.account_id, OLD.id, 'auth_close', '00:11:22:33:44:41', 1024, 2048, datetime('now'), datetime('now'));
END;
SQL

out=$( "$ADMIN" device-remove 41 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "database" ]; then
	pass "admin.sh device-remove fails closed when usage event appears during delete transaction"
else
	fail "admin.sh device-remove usage race returned rc=$rc output='$out'"
fi

dev41_count=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=41;")
if [ "$dev41_count" -eq 1 ]; then
	pass "Concurrent usage race: device 41 remained intact in database"
else
	fail "Concurrent usage race: device 41 was incorrectly deleted"
fi

usage41_count=$(sqlite3 "$DB" "SELECT count(*) FROM usage_events WHERE device_id=41;")
if [ "$usage41_count" -eq 0 ]; then
	pass "Concurrent usage race: aborted transaction rolled back inserted usage event"
else
	fail "Concurrent usage race: usage event row was unexpectedly retained"
fi

evt_race_usage=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND account_id=2 AND detail='reason=database:device_id=41';")
if [ "$evt_race_usage" -ge 1 ]; then
	pass "admin.sh logged device_remove_denied for usage race condition"
else
	fail "admin.sh did not log device_remove_denied for usage race condition"
fi

sqlite3 "$DB" "DROP TRIGGER sim_race_usage;"

# ==============================================================================
# 14. Removal Precedence: Live Session Rejection over Historical
# ==============================================================================
# Device 50 has both live session and closed session. Removing it must reject with live-session first.
out=$( "$ADMIN" device-remove 50 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "live-session" ]; then
	pass "admin.sh device-remove gives precedence to live-session over usage-history for device 50"
else
	fail "admin.sh device-remove precedence failed for device 50: rc=$rc output='$out'"
fi

evt_prec=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='device_remove_denied' AND detail='reason=live-session:device_id=50';")
if [ "$evt_prec" -ge 1 ]; then
	pass "admin.sh logged device_remove_denied with reason=live-session:device_id=50"
else
	fail "admin.sh did not log live-session reason for device 50"
fi

# ==============================================================================
# 15. LuCI Controller and View Guidance Contracts
# ==============================================================================
if grep -F 'Error: historical device: use Reassign. Archive is planned separately' "$CONTROLLER" >/dev/null; then
	pass "LuCI controller provides accurate guidance for historical device removal"
else
	fail "LuCI controller missing accurate historical device guidance"
fi

if grep -F 'Error: live session: Disconnect first' "$CONTROLLER" >/dev/null; then
	pass "LuCI controller provides human-readable guidance for live session device removal"
else
	fail "LuCI controller missing live session guidance"
fi

if grep -F 'Error: database failure: retry and inspect Events' "$CONTROLLER" >/dev/null; then
	pass "LuCI controller provides human-readable guidance for database failure"
else
	fail "LuCI controller missing database failure guidance"
fi

if grep -F 'for historical devices, use Reassign; for live sessions, Disconnect first' "$VIEW" >/dev/null; then
	pass "devices.htm view displays user-facing explanation on device management"
else
	fail "devices.htm missing user-facing explanation"
fi

if grep -F 'Historical device retained for accounting; use Reassign. Archive is planned separately.' "$VIEW" >/dev/null; then
	pass "devices.htm disables historical device removal with exact non-misleading guidance"
else
	fail "devices.htm missing exact historical device guidance"
fi

if grep -F 'Historical (use Reassign)' "$VIEW" >/dev/null; then
	pass "devices.htm displays compact Historical (use Reassign) hint"
else
	fail "devices.htm missing compact historical hint"
fi

if grep -F 'Remove (Locked)' "$VIEW" >/dev/null && grep -F 'Remove (Active)' "$VIEW" >/dev/null; then
	pass "devices.htm renders distinct disabled buttons for locked and active states"
else
	fail "devices.htm missing locked or active disabled buttons"
fi

if grep -F 'device.lifecycle_state == "live"' "$VIEW" >/dev/null; then
	pass "devices.htm enforces live session precedence before historical checks"
else
	fail "devices.htm missing live lifecycle_state precedence check"
fi

# ==============================================================================
# 16. Pending Session Lifecycle & Actionable UI Regression Tests
# ==============================================================================
# Requirement 1: Pending device removal is disabled
out=$( "$ADMIN" device-remove 11 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "live-session" ]; then
	pass "Regression: admin.sh device-remove disabled on pending device with live-session"
else
	fail "Regression: admin.sh device-remove on pending device returned rc=$rc output='$out'"
fi

dev11_check=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=11;")
if [ "$dev11_check" -eq 1 ]; then
	pass "Regression: pending device 11 remained intact in database"
else
	fail "Regression: pending device 11 was deleted from database"
fi

rpc_rem_11=$(printf '{"id":11}' | "$RPC" call device_remove 2>&1 || true)
if printf '%s' "$rpc_rem_11" | grep -F '"ok": false' >/dev/null && \
   printf '%s' "$rpc_rem_11" | grep -F '"error": "live-session"' >/dev/null; then
	pass "Regression: RPC device_remove fails closed with live-session for pending device"
else
	fail "Regression: RPC device_remove pending device response incorrect: $rpc_rem_11"
fi

# Requirement 2: The user sees an actionable state
# 2a. Live session indicator includes pending sessions
dev_list_fresh=$("$ADMIN" device-list)
d11_live_count=$(printf '%s\n' "$dev_list_fresh" | grep '^11|' | awk -F'|' '{print $8}')
if [ "$d11_live_count" -ge 1 ]; then
	pass "Regression: admin_device_list displayed live-session indicator includes pending sessions (count=$d11_live_count)"
else
	fail "Regression: admin_device_list failed to include pending sessions in live_sessions (count='$d11_live_count')"
fi

# 2b. View renders Disconnect action for lifecycle_state == 'live'
if grep -F 'device.lifecycle_state == "live" or (device.live_sessions and device.live_sessions > 0)' "$VIEW" | grep -F 'force-deauth' >/dev/null; then
	pass "Regression: devices.htm renders Disconnect action whenever lifecycle_state == 'live'"
else
	fail "Regression: devices.htm missing Disconnect action for lifecycle_state == 'live'"
fi

# 2c. Backend force-deauth works safely on device with pending session
rm -f "$OPEN_HOTSPOT_DEAUTH_LOG"
out=$( "$ADMIN" device-force-deauth 11 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
	pass "Regression: admin.sh device-force-deauth safely handled device with pending session"
else
	fail "Regression: admin.sh device-force-deauth on pending device failed: rc=$rc output='$out'"
fi

if grep -Fx '00:11:22:33:44:02' "$OPEN_HOTSPOT_DEAUTH_LOG" >/dev/null 2>&1; then
	pass "Regression: device-force-deauth dispatched MAC to opennds deauth helper"
else
	fail "Regression: device-force-deauth did not dispatch MAC to opennds deauth helper"
fi

evt_force_deauth=$(sqlite3 "$DB" "SELECT count(*) FROM admin_events WHERE action='force_deauth' AND account_id=1 AND detail='00:11:22:33:44:02';")
if [ "$evt_force_deauth" -ge 1 ]; then
	pass "Regression: admin.sh logged force_deauth event in admin_events"
else
	fail "Regression: admin.sh did not log force_deauth event"
fi

rpc_deauth_11=$(printf '{"id":11}' | "$RPC" call device_force_deauth 2>&1)
if printf '%s' "$rpc_deauth_11" | grep -F '"ok": true' >/dev/null; then
	pass "Regression: RPC device_force_deauth succeeds for device with pending session"
else
	fail "Regression: RPC device_force_deauth failed: $rpc_deauth_11"
fi

# Requirement 3: Live precedence remains correct when device has both history and pending session
sqlite3 "$DB" <<SQL
INSERT INTO devices(id, account_id, mac, status) VALUES (51, 1, '00:11:22:33:44:51', 'active');
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state, closed_at)
VALUES (511, 1, 51, 'sess-closed-51', datetime('now'), datetime('now'), 'closed', datetime('now'));
INSERT INTO active_sessions(id, account_id, device_id, session_key, started_at, last_seen_at, state)
VALUES (512, 1, 51, 'sess-pending-51', datetime('now'), datetime('now'), 'pending');
SQL

d51_line=$("$ADMIN" device-list | grep '^51|' || true)
d51_live=$(printf '%s' "$d51_line" | awk -F'|' '{print $8}')
d51_hist=$(printf '%s' "$d51_line" | awk -F'|' '{print $9}')
d51_state=$(printf '%s' "$d51_line" | awk -F'|' '{print $10}')

if [ "$d51_live" -ge 1 ] && [ "$d51_hist" = "1" ] && [ "$d51_state" = "live" ]; then
	pass "Regression: device 51 with closed history + pending session reports live_sessions=$d51_live, has_history=1, lifecycle_state=live"
else
	fail "Regression: device 51 state mismatch: live='$d51_live' hist='$d51_hist' state='$d51_state'"
fi

out=$( "$ADMIN" device-remove 51 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "live-session" ]; then
	pass "Regression: device-remove 51 gives precedence to live-session over usage-history"
else
	fail "Regression: device-remove 51 precedence failed: rc=$rc output='$out'"
fi

# Requirement 4: No historical device becomes removable
d12_line=$("$ADMIN" device-list | grep '^12|' || true)
d12_live=$(printf '%s' "$d12_line" | awk -F'|' '{print $8}')
d12_hist=$(printf '%s' "$d12_line" | awk -F'|' '{print $9}')
d12_state=$(printf '%s' "$d12_line" | awk -F'|' '{print $10}')

if [ "$d12_live" = "0" ] && [ "$d12_hist" = "1" ] && [ "$d12_state" = "historical" ]; then
	pass "Regression: historical device 12 has live_sessions=0, has_history=1, lifecycle_state=historical"
else
	fail "Regression: historical device 12 mismatch: live='$d12_live' hist='$d12_hist' state='$d12_state'"
fi

out=$( "$ADMIN" device-remove 12 2>&1 ) && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ "$out" = "usage-history" ]; then
	pass "Regression: historical device 12 removal rejected with usage-history"
else
	fail "Regression: historical device 12 removal was not rejected with usage-history: rc=$rc output='$out'"
fi

dev12_check=$(sqlite3 "$DB" "SELECT count(*) FROM devices WHERE id=12;")
if [ "$dev12_check" -eq 1 ]; then
	pass "Regression: historical device 12 was not removed from database"
else
	fail "Regression: historical device 12 was incorrectly deleted"
fi

printf '\ntest_device_lifecycle: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
