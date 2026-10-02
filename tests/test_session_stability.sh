#!/bin/sh
set -eu

# test_session_stability.sh — Regression test for client eviction & session lifecycle stability
#
# Covers:
# 1. opennds_authenticated_macs vs opennds_live_macs parsing
# 2. Case-insensitive MAC matching across db.sh functions
# 3. policy_period_start population during db_auth_consume
# 4. Safe reconcile_stale: preserving authenticated clients, ignoring preauthenticated probes
# 5. Reconcile rogue client deauth success: native_restore_reconciled logging without leak
# 6. Reconcile rogue client deauth failure: native_restore_reconcile_failed logging with exit code
# 7. rpcd dev_diagnose pure-shell watchdog without external timeout command
# 8. cycle.sh runtime guard simulation: retry before reload when openNDS is alive
# 9. Cycle policy refresh simulation: no redundant opennds_apply_session_policy when window matches
# 10. Cycle policy refresh failure simulation: safe event details and active session preserved in SQLite
#
# NOTE: Tests 8, 9, and 10 are contract and logic simulations of the cycle algorithm
# under isolated mock conditions. They verify algorithm branching, database state
# changes, and event logging contracts, but do not execute /usr/lib/open-hotspot/cycle.sh
# itself (which requires root, /var/run flock, and a live openNDS daemon). Full end-to-end
# cycle execution remains a physical router acceptance gate.

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TMPDIR=$(mktemp -d /tmp/oh-stability.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PASSES=0
FAILURES=0

pass() { PASSES=$((PASSES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# --- Test 1: opennds_authenticated_macs extraction and casing ---
export OPEN_HOTSPOT_NDSCTL_BIN="$TMPDIR/mock-ndsctl"
cat << 'EOF' > "$OPEN_HOTSPOT_NDSCTL_BIN"
#!/bin/sh
cat << 'STATUS'
================== Client 0 ==================
  IP: 192.168.1.100 MAC: aa:bb:cc:dd:ee:01
  State: Authenticated
================== Client 1 ==================
  IP: 192.168.1.101 MAC: AA:BB:CC:DD:EE:02
  State: Preauthenticated
================== Client 2 ==================
  State: Authenticated
  MAC: 11:22:33:44:55:66
STATUS
EOF
chmod +x "$OPEN_HOTSPOT_NDSCTL_BIN"

. "$PROJECT/starter-kit/root/usr/lib/open-hotspot/opennds.sh"

auth_macs=$(opennds_authenticated_macs)
if printf '%s\n' "$auth_macs" | grep -q 'AA:BB:CC:DD:EE:01' && \
   printf '%s\n' "$auth_macs" | grep -q '11:22:33:44:55:66' && \
   ! printf '%s\n' "$auth_macs" | grep -qi 'AA:BB:CC:DD:EE:02'; then
	pass "opennds_authenticated_macs extracts authenticated clients and filters out preauthenticated probes"
else
	fail "opennds_authenticated_macs output incorrect: $auth_macs"
fi

live_macs=$(opennds_live_macs)
if printf '%s\n' "$live_macs" | grep -q 'AA:BB:CC:DD:EE:01' && \
   printf '%s\n' "$live_macs" | grep -q 'AA:BB:CC:DD:EE:02' && \
   printf '%s\n' "$live_macs" | grep -q '11:22:33:44:55:66'; then
	pass "opennds_live_macs normalizes all client MACs to uppercase"
else
	fail "opennds_live_macs output incorrect: $live_macs"
fi

# --- Test 2: SQLite COLLATE NOCASE MAC matching ---
TEST_DB="$TMPDIR/test.db"
export OPEN_HOTSPOT_DB_PATH="$TEST_DB"
export DB_PATH="$TEST_DB"
sqlite3 "$TEST_DB" < "$PROJECT/starter-kit/root/usr/lib/open-hotspot/schema.sql"

. "$PROJECT/starter-kit/root/usr/lib/open-hotspot/db.sh"

# Insert test account, device with UPPERCASE MAC, and active session
sqlite3 "$TEST_DB" << 'EOF'
INSERT OR REPLACE INTO profiles (id, name, period_type, time_limit_s, upload_limit_b, download_limit_b, upload_rate_kbps, download_rate_kbps, max_devices)
VALUES (1, 'default', 'daily', 3600, 1048576, 1048576, 1000, 1000, 5);

INSERT INTO accounts (id, username, pin_hash, pin_salt, pin_iter, profile_id, status)
VALUES (1, 'testuser', 'dummyhash', 'dummysalt', 1000, 1, 'active');

INSERT INTO devices (id, account_id, mac, status, last_seen, updated_at)
VALUES (1, 1, 'AA:BB:CC:DD:EE:FF', 'active', datetime('now'), datetime('now'));

INSERT INTO active_sessions (account_id, device_id, session_key, started_at, last_seen_at, state, policy_period_start)
VALUES (1, 1, '11112222333344445555666677778888', datetime('now'), datetime('now'), 'active', '2026-10-02T00:00:00Z');
EOF

# Query with LOWERCASE MAC
count_lower=$(db_active_session_count_by_mac "aa:bb:cc:dd:ee:ff")
if [ "$count_lower" -eq 1 ]; then
	pass "db_active_session_count_by_mac matches case-insensitively"
else
	fail "db_active_session_count_by_mac failed for lowercase MAC (got $count_lower)"
fi

key_lower=$(db_session_key_by_mac "aa:bb:cc:dd:ee:ff")
if [ "$key_lower" = "11112222333344445555666677778888" ]; then
	pass "db_session_key_by_mac matches case-insensitively"
else
	fail "db_session_key_by_mac failed for lowercase MAC (got $key_lower)"
fi

# --- Test 3: db_auth_consume populates policy_period_start ---
# Setup auth transaction with snapshot containing 7th field as period_start
AUTH_KEY="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SNAPSHOT="1|3600|1048576|1048576|1000|1000|2026-10-02T12:00:00Z|2026-10-03T12:00:00Z"
sqlite3 "$TEST_DB" << EOF
INSERT INTO auth_transactions (auth_key, account_id, device_mac, profile_id, policy_snapshot, expires_at, state)
VALUES ('$AUTH_KEY', 1, '00:11:22:33:44:55', 1, '$SNAPSHOT', datetime('now', '+15 minutes'), 'pending');
EOF

consume_out=$(db_auth_consume "$AUTH_KEY" "00:11:22:33:44:55" "$(date -u +%s)")
period_stored=$(sqlite3 "$TEST_DB" "SELECT policy_period_start FROM active_sessions WHERE session_key='$AUTH_KEY';")
if [ "$period_stored" = "2026-10-02T12:00:00Z" ]; then
	pass "db_auth_consume populates policy_period_start from policy_snapshot"
else
	fail "db_auth_consume did not populate policy_period_start (got: '$period_stored')"
fi

# --- Test 4: session-restore.sh reconcile_stale with mixed clients ---
# Prepare mock ndsctl that records deauth calls
DEAUTH_LOG="$TMPDIR/deauth.log"
cat << EOF > "$OPEN_HOTSPOT_NDSCTL_BIN"
#!/bin/sh
case "\$1" in
	status)
		cat << 'STATUS'
Version: 11.0.0
Current clients: 2
================== Client 0 ==================
  IP: 192.168.1.50 MAC: aa:bb:cc:dd:ee:ff
  State: Authenticated
================== Client 1 ==================
  IP: 192.168.1.51 MAC: 99:88:77:66:55:44
  State: Preauthenticated
STATUS
		;;
	deauth)
		printf '%s\n' "\$2" >> "$DEAUTH_LOG"
		;;
	*)
		exit 0
		;;
esac
EOF
chmod +x "$OPEN_HOTSPOT_NDSCTL_BIN"

# Mock uci for session_restore mode disabled
MOCK_UCI="$TMPDIR/mock-uci"
cat << 'EOF' > "$MOCK_UCI"
#!/bin/sh
if [ "$1" = "-q" ] && [ "$2" = "get" ] && [ "$3" = "open-hotspot.global.session_restore" ]; then
	echo "disabled"
	exit 0
fi
exit 0
EOF
chmod +x "$MOCK_UCI"

export OPEN_HOTSPOT_UCI_BIN="$MOCK_UCI"
export OPEN_HOTSPOT_DB_HELPER="$PROJECT/starter-kit/root/usr/lib/open-hotspot/db.sh"
export OPEN_HOTSPOT_NDS_HELPER="$PROJECT/starter-kit/root/usr/lib/open-hotspot/opennds.sh"
export OPEN_HOTSPOT_ADAPTER_DIR="$PROJECT/starter-kit/root/usr/lib/open-hotspot/adapters"

# Run reconcile
sh "$PROJECT/starter-kit/root/usr/lib/open-hotspot/session-restore.sh" reconcile

if [ ! -f "$DEAUTH_LOG" ]; then
	pass "reconcile_stale preserved active authenticated client and ignored preauthenticated probe"
else
	fail "reconcile_stale incorrectly deauthenticated: $(cat "$DEAUTH_LOG")"
fi

# Ensure the active session remains active in SQLite
session_state=$(sqlite3 "$TEST_DB" "SELECT state FROM active_sessions WHERE session_key='11112222333344445555666677778888';")
if [ "$session_state" = "active" ]; then
	pass "active session state remains 'active' in SQLite after reconcile"
else
	fail "active session state changed to '$session_state'"
fi

# --- Test 5: Reconcile correctly deauths rogue authenticated client ---
cat << EOF > "$OPEN_HOTSPOT_NDSCTL_BIN"
#!/bin/sh
case "\$1" in
	status)
		cat << 'STATUS'
Version: 11.0.0
Current clients: 1
================== Client 0 ==================
  IP: 192.168.1.99 MAC: DE:AD:BE:EF:00:01
  State: Authenticated
STATUS
		;;
	deauth)
		printf '%s\n' "\$2" >> "$DEAUTH_LOG"
		;;
	*)
		exit 0
		;;
esac
EOF

sh "$PROJECT/starter-kit/root/usr/lib/open-hotspot/session-restore.sh" reconcile
if [ -f "$DEAUTH_LOG" ] && grep -qE 'DE:AD:BE:EF:00:01|192\.168\.1\.99' "$DEAUTH_LOG"; then
	pass "reconcile_stale deauthenticated rogue unmanaged authenticated client"
else
	fail "reconcile_stale did not deauthenticate rogue client"
fi

# Verify success event logging and no secret leaks
event_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM admin_events WHERE action='native_restore_reconciled' AND detail='no-manager-session';")
if [ "$event_count" -ge 1 ]; then
	pass "reconcile_stale logged native_restore_reconciled with 'no-manager-session'"
else
	fail "reconcile_stale did not log native_restore_reconciled"
fi

leak_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM admin_events WHERE action='native_restore_reconciled' AND (detail LIKE '%DE:AD:BE:EF%' OR detail LIKE '%192.168%' OR detail LIKE '%dummy%');")
if [ "$leak_count" -eq 0 ]; then
	pass "native_restore_reconciled event contains no MAC, IP, or credential leaks"
else
	fail "native_restore_reconciled event leaked sensitive data"
fi

# --- Test 6: Reconcile logs native_restore_reconcile_failed when deauth fails ---
cat << EOF > "$OPEN_HOTSPOT_NDSCTL_BIN"
#!/bin/sh
case "\$1" in
	status)
		cat << 'STATUS'
Version: 11.0.0
Current clients: 1
================== Client 0 ==================
  IP: 192.168.1.98 MAC: DE:AD:BE:EF:00:02
  State: Authenticated
STATUS
		;;
	deauth)
		exit 7
		;;
	*)
		exit 0
		;;
esac
EOF

sh "$PROJECT/starter-kit/root/usr/lib/open-hotspot/session-restore.sh" reconcile
fail_event_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM admin_events WHERE action='native_restore_reconcile_failed' AND detail='reconcile:deauth_rc=7';")
if [ "$fail_event_count" -ge 1 ]; then
	pass "reconcile_stale logged native_restore_reconcile_failed with safe return code"
else
	fail "reconcile_stale did not log native_restore_reconcile_failed with reconcile:deauth_rc=7"
fi

fail_leak_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM admin_events WHERE action='native_restore_reconcile_failed' AND (detail LIKE '%DE:AD:BE:EF%' OR detail LIKE '%192.168%');")
if [ "$fail_leak_count" -eq 0 ]; then
	pass "native_restore_reconcile_failed event contains no MAC or IP leaks"
else
	fail "native_restore_reconcile_failed leaked sensitive data"
fi

# --- Test 7: rpcd dev_diagnose watchdog without timeout command ---
RPCD_BIN="$PROJECT/starter-kit/root/usr/libexec/rpcd/open_hotspot"
MOCK_DIAGNOSE="$TMPDIR/mock-diagnose.sh"
cat << 'EOF' > "$MOCK_DIAGNOSE"
#!/bin/sh
echo "diagnostic health check ok"
exit 0
EOF
chmod +x "$MOCK_DIAGNOSE"

VERSION_FILE="$TMPDIR/open-hotspot.version"
printf '1.2.0-r93\n' > "$VERSION_FILE"

# Create a PATH environment that hides the external timeout command
CLEAN_BIN="$TMPDIR/clean_bin"
mkdir -p "$CLEAN_BIN"
for cmd in sh bash sed awk grep head cut cat date mktemp rm kill sleep wait tr base64 python3; do
	cmd_path=$(command -v "$cmd" 2>/dev/null || true)
	if [ -n "$cmd_path" ]; then
		ln -sf "$cmd_path" "$CLEAN_BIN/$cmd"
	fi
done

output=$(
	printf '{}' | \
	PATH="$CLEAN_BIN" \
	OPEN_HOTSPOT_DIAGNOSE="$MOCK_DIAGNOSE" \
	OPEN_HOTSPOT_VERSION_FILE="$VERSION_FILE" \
	OPEN_HOTSPOT_JSHN_SH="$PROJECT/tests/fixtures/mock-jshn.sh" \
	OPEN_HOTSPOT_DB_PATH="$TEST_DB" \
	"$RPCD_BIN" call dev_diagnose
)

if printf '%s\n' "$output" | grep -qE '"exit_code":[[:space:]]*0' && \
   printf '%s\n' "$output" | grep -q 'diagnostic health check ok' && \
   printf '%s\n' "$output" | grep -qE '"pkg_version":[[:space:]]*"1\.2\.0-r93"'; then
	pass "rpc_dev_diagnose succeeded with pure-shell watchdog and version file detection"
else
	fail "rpc_dev_diagnose failed with clean environment: $output"
fi

# --- Test 8: cycle.sh runtime guard retries before reload when openNDS is alive ---
GUARD_LOG="$TMPDIR/guard_reload.log"
GUARD_VALIDATE_STATE="$TMPDIR/guard_validate.state"
echo "1" > "$GUARD_VALIDATE_STATE"

mock_validate() {
	count=$(cat "$GUARD_VALIDATE_STATE")
	if [ "$count" = "1" ]; then
		echo "2" > "$GUARD_VALIDATE_STATE"
		return 1
	else
		return 0
	fi
}
mock_pidof() {
	return 0
}
mock_reload() {
	echo "RELOAD_INVOKED" >> "$GUARD_LOG"
	return 0
}

run_guard() {
	validate_rc=0
	if mock_validate; then
		return 0
	fi
	validate_rc=$?

	if mock_pidof opennds >/dev/null 2>&1; then
		if mock_validate; then
			return 0
		fi
	fi

	reload_rc=0
	mock_reload || reload_rc=$?
	return "$reload_rc"
}

guard_result=0
run_guard || guard_result=$?

if [ "$guard_result" -eq 0 ] && [ ! -f "$GUARD_LOG" ]; then
	pass "cycle runtime guard simulation: retried and avoided opennds reload while daemon process was alive"
else
	fail "cycle runtime guard failed: result=$guard_result reload_log=$(cat "$GUARD_LOG" 2>/dev/null || echo 'none')"
fi

# --- Test 9: cycle policy refresh is not repeated when policy_period_start matches current period ---
. "$PROJECT/starter-kit/root/usr/lib/open-hotspot/period.sh"
. "$PROJECT/starter-kit/root/usr/lib/open-hotspot/quota.sh"

now_epoch=$(date -u '+%s')
current_window=$(period_window_effective "daily" "" "$now_epoch")
current_start=$(printf '%s' "$current_window" | cut -f1)

# Ensure account 1 session has policy_period_start set to current_start
sqlite3 "$TEST_DB" << EOF
UPDATE active_sessions SET policy_period_start='$current_start' WHERE account_id=1;
EOF

POLICY_APPLY_LOG="$TMPDIR/policy_apply.log"
rm -f "$POLICY_APPLY_LOG"

# Simulate cycle.sh policy refresh loop
sqlite3 -batch "$TEST_DB" "
	SELECT DISTINCT d.mac, a.id, a.profile_id, COALESCE(a.renewed_at,''),
	       COALESCE(s.policy_period_start,'')
	FROM devices d
	JOIN accounts a ON a.id = d.account_id
	JOIN active_sessions s ON s.device_id = d.id
	WHERE d.status='active' AND a.status='active' AND a.deleted_at IS NULL
	AND s.state='active';" | while IFS='|' read -r mac acct_id profile_id renewed_at policy_period_start; do
	[ -n "$mac" ] || continue
	prof=$(db_profile_get "$profile_id")
	period_type=$(printf '%s' "$prof" | cut -d'|' -f1)
	window=$(period_window_effective "$period_type" "$renewed_at" "$now_epoch") || continue
	period_start=$(printf '%s' "$window" | cut -f1)

	# Key check from cycle.sh
	[ "$policy_period_start" = "$period_start" ] && continue

	echo "POLICY_APPLIED_FOR_$mac" >> "$POLICY_APPLY_LOG"
done

if [ ! -f "$POLICY_APPLY_LOG" ]; then
	pass "cycle policy refresh simulation: correctly skipped because policy_period_start matched current period"
else
	fail "policy refresh was redundantly triggered: $(cat "$POLICY_APPLY_LOG")"
fi

# --- Test 10: cycle policy refresh failure logs policy_refresh_failed and preserves active session ---
# Set policy_period_start to an old window to trigger refresh
sqlite3 "$TEST_DB" << EOF
UPDATE active_sessions SET policy_period_start='2020-01-01T00:00:00Z' WHERE account_id=1;
EOF

# Simulate policy refresh failure when opennds_apply_session_policy fails
sqlite3 -batch "$TEST_DB" "
	SELECT DISTINCT d.mac, a.id, a.profile_id, COALESCE(a.renewed_at,''),
	       COALESCE(s.policy_period_start,'')
	FROM devices d
	JOIN accounts a ON a.id = d.account_id
	JOIN active_sessions s ON s.device_id = d.id
	WHERE d.status='active' AND a.status='active' AND a.deleted_at IS NULL
	AND s.state='active';" | while IFS='|' read -r mac acct_id profile_id renewed_at policy_period_start; do
	[ -n "$mac" ] || continue
	prof=$(db_profile_get "$profile_id")
	period_type=$(printf '%s' "$prof" | cut -d'|' -f1)
	window=$(period_window_effective "$period_type" "$renewed_at" "$now_epoch") || continue
	period_start=$(printf '%s' "$window" | cut -f1)

	[ "$policy_period_start" = "$period_start" ] && continue

	# Simulate failure of opennds_apply_session_policy (returns 1)
	db_log_event policy_refresh_failed "$acct_id" "policy:period=$period_type:window=$period_start" || true
done

# Check event logged with safe detail
refresh_event=$(sqlite3 "$TEST_DB" "SELECT detail FROM admin_events WHERE action='policy_refresh_failed' ORDER BY id DESC LIMIT 1;")
if printf '%s\n' "$refresh_event" | grep -qE '^policy:period=daily:window='; then
	pass "cycle policy refresh simulation: policy_refresh_failed logged with safe detail format: $refresh_event"
else
	fail "policy_refresh_failed not logged or format invalid: $refresh_event"
fi

# Check that refresh event detail has no sensitive leaks
refresh_leak=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM admin_events WHERE action='policy_refresh_failed' AND (detail LIKE '%AA:BB%' OR detail LIKE '%dummy%');")
if [ "$refresh_leak" -eq 0 ]; then
	pass "cycle policy refresh simulation: event contains no MAC, IP, or credential leaks"
else
	fail "policy_refresh_failed event leaked sensitive data"
fi

# Ensure active sessions remain active in SQLite
active_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM active_sessions WHERE account_id=1 AND state='active';")
total_count=$(sqlite3 "$TEST_DB" "SELECT count(*) FROM active_sessions WHERE account_id=1;")
if [ "$active_count" -gt 0 ] && [ "$active_count" -eq "$total_count" ]; then
	pass "cycle policy refresh simulation: active sessions remain 'active' in SQLite despite failure"
else
	fail "active session was corrupted or closed during policy refresh failure (active=$active_count total=$total_count)"
fi

# --- Summary ---
printf 'test_session_stability: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
exit 0
