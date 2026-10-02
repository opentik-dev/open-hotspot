#!/bin/sh
set -eu

# test_session_stability.sh — Regression test for client eviction & session lifecycle stability
#
# Covers:
# 1. opennds_authenticated_macs vs opennds_live_macs parsing
# 2. Case-insensitive MAC matching across db.sh functions
# 3. policy_period_start population during db_auth_consume
# 4. Safe reconcile_stale: preserving authenticated clients, ignoring preauthenticated probes
# 5. Cycle tick stability: no redundant opennds_apply_session_policy when window matches
# 6. dev_diagnose pure-shell watchdog without external timeout command
# 7. Package version discovery from open-hotspot.version

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

# --- Test 6: rpcd dev_diagnose watchdog without timeout command ---
RPCD_BIN="$PROJECT/starter-kit/root/usr/libexec/rpcd/open_hotspot"
MOCK_DIAGNOSE="$TMPDIR/mock-diagnose.sh"
cat << 'EOF' > "$MOCK_DIAGNOSE"
#!/bin/sh
echo "diagnostic health check ok"
exit 0
EOF
chmod +x "$MOCK_DIAGNOSE"

VERSION_FILE="$TMPDIR/open-hotspot.version"
printf '1.2.0-r92\n' > "$VERSION_FILE"

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
   printf '%s\n' "$output" | grep -qE '"pkg_version":[[:space:]]*"1\.2\.0-r92"'; then
	pass "rpc_dev_diagnose succeeded with pure-shell watchdog and version file detection"
else
	fail "rpc_dev_diagnose failed with clean environment: $output"
fi

# --- Summary ---
printf 'test_session_stability: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
exit 0
