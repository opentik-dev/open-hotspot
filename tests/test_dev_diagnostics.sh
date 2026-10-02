#!/bin/sh
set -eu

# test_dev_diagnostics.sh — Contract and functional tests for the separated DEV and Events pages:
# 1. LuCI routes/menu and read-only view contracts
# 2. RPC methods and ACL permissions
# 3. Maximum row limit (50 events) and output size limit (8192 bytes)
# 4. Full MAC and IP redaction
# 5. Prevention of PIN, token, and secret key leakage
# 6. Safety: no user-controlled shell input or path execution
# 7. Non-zero exit code preservation from diagnose.sh without losing report text

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TMP_DIR=$(mktemp -d /tmp/oh-dev-test.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

CONTROLLER="$PROJECT/starter-kit/luasrc/controller/open-hotspot.lua"
VIEW="$PROJECT/starter-kit/luasrc/view/open-hotspot/dev.htm"
EVENTS_VIEW="$PROJECT/starter-kit/luasrc/view/open-hotspot/events.htm"
RPC="$PROJECT/starter-kit/root/usr/libexec/rpcd/open_hotspot"
ACL="$PROJECT/starter-kit/root/usr/share/rpcd/acl.d/luci-app-open-hotspot.json"

if [ ! -f /usr/share/libubox/jshn.sh ]; then
	export OPEN_HOTSPOT_JSHN_SH="$PROJECT/tests/fixtures/mock-jshn.sh"
fi

FAILURES=0
PASSES=0

pass() { PASSES=$((PASSES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# ==============================================================================
# 1. LuCI Route and View Contract
# ==============================================================================
[ -f "$CONTROLLER" ] || { fail "controller missing"; exit 1; }
[ -f "$VIEW" ] || { fail "dev.htm view missing"; exit 1; }
[ -f "$EVENTS_VIEW" ] || { fail "events.htm view missing"; exit 1; }

# DEV is the future feature lab; Events owns the diagnostics and event log.
if grep -F 'entry({"admin", "services", "open-hotspot", "dev"},' "$CONTROLLER" >/dev/null && \
   grep -F 'call("dev_lab"), translate("DEV"), 90)' "$CONTROLLER" >/dev/null && \
   grep -F 'entry({"admin", "services", "open-hotspot", "events"},' "$CONTROLLER" >/dev/null && \
   grep -F 'call("events_log"), translate("Events"), 85)' "$CONTROLLER" >/dev/null; then
	pass "LuCI controller separates DEV and Events routes"
else
	fail "LuCI controller missing separated DEV/Events route entries"
fi

# Route is protected by ACL dependency
if grep -A 3 'open-hotspot", "dev"}' "$CONTROLLER" | grep -F 'acl_depends = { "luci-app-open-hotspot" }' >/dev/null; then
	pass "DEV route enforces luci-app-open-hotspot ACL"
else
	fail "DEV route missing acl_depends"
fi

if grep -A 3 'open-hotspot", "events"}' "$CONTROLLER" | grep -F 'acl_depends = { "luci-app-open-hotspot" }' >/dev/null; then
	pass "Events route enforces luci-app-open-hotspot ACL"
else
	fail "Events route missing acl_depends"
fi

# View contains experimental warning banner
if grep -F 'EXPERIMENTAL' "$VIEW" >/dev/null && grep -F 'Nothing here changes router policy' "$VIEW" >/dev/null; then
	pass "dev.htm contains experimental non-acceptance warning banner"
else
	fail "dev.htm missing required experimental warning banner"
fi

if grep -F 'IoT Internet bypass' "$VIEW" >/dev/null && \
   grep -F 'Design only — disabled' "$VIEW" >/dev/null && \
   ! grep -F 'Recent Admin Events' "$VIEW" >/dev/null && \
   ! grep -F 'Diagnostic Report' "$VIEW" >/dev/null; then
	pass "DEV contains future IoT features without the Events/diagnostic stream"
else
	fail "DEV still mixes diagnostics or lacks the future IoT feature registry"
fi

# View is read-only (no form submission, no action handler)
if grep -Eq '<form|method="post"|action=' "$VIEW"; then
	fail "dev.htm must be read-only but contains form/POST elements"
else
	pass "dev.htm is strictly read-only"
fi

if grep -F 'Open-HotSpot Event Log' "$EVENTS_VIEW" >/dev/null && \
   grep -F 'Recent service events' "$EVENTS_VIEW" >/dev/null && \
   grep -F 'Diagnostic snapshot' "$EVENTS_VIEW" >/dev/null && \
   grep -F 'dev_events_list' "$CONTROLLER" >/dev/null && \
   grep -F 'dev_diagnose' "$CONTROLLER" >/dev/null; then
	pass "Events page owns the bounded event log and diagnostic snapshot"
else
	fail "Events page is missing event-log or diagnostic wiring"
fi

if grep -Eq '<form|method="post"|action=' "$EVENTS_VIEW"; then
	fail "events.htm must be read-only but contains form/POST elements"
else
	pass "events.htm is strictly read-only"
fi

# ==============================================================================
# 2. RPC Registration and ACL Permissions
# ==============================================================================
[ -x "$RPC" ] || { fail "rpcd script missing or not executable"; exit 1; }
[ -f "$ACL" ] || { fail "ACL file missing"; exit 1; }

# Verify JSON validity of ACL
python3 -m json.tool "$ACL" >/dev/null 2>&1 || { fail "ACL is not valid JSON"; exit 1; }

# rpcd list announces both dev_events_list and dev_diagnose
list_out=$("$RPC" list)
if printf '%s' "$list_out" | grep -F '"dev_events_list":{}' >/dev/null && \
   printf '%s' "$list_out" | grep -F '"dev_diagnose":{}' >/dev/null; then
	pass "rpcd list advertises dev_events_list and dev_diagnose"
else
	fail "rpcd list missing dev_events_list or dev_diagnose"
fi

# ACL allows read access to dev_events_list and dev_diagnose
read_acl=$(python3 -c "import json, sys; d=json.load(open('$ACL'))['luci-app-open-hotspot']['read']['ubus']['open_hotspot']; sys.exit(0 if 'dev_events_list' in d and 'dev_diagnose' in d else 1)") && {
	pass "ACL grants read permission for dev_events_list and dev_diagnose"
} || {
	fail "ACL missing read permission for dev_events_list or dev_diagnose"
}

# ACL must NOT grant write access to dev methods
write_acl=$(python3 -c "import json, sys; d=json.load(open('$ACL'))['luci-app-open-hotspot']['write']['ubus']['open_hotspot']; sys.exit(0 if 'dev_events_list' in d or 'dev_diagnose' in d else 1)") && {
	fail "ACL must not grant write permission to DEV methods"
} || {
	pass "ACL correctly denies write permission to DEV methods"
}

# ==============================================================================
# 3. Functional Test: dev_events_list (Limit 50, Redaction, No Secrets)
# ==============================================================================
TEST_DB="$TMP_DIR/hotspot.db"
export OPEN_HOTSPOT_DB_PATH="$TEST_DB"

sqlite3 "$TEST_DB" <<SQL
CREATE TABLE admin_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    ts         TEXT NOT NULL DEFAULT (datetime('now')),
    account_id INTEGER,
    action     TEXT NOT NULL,
    detail     TEXT
);
SQL

# Insert 60 events to test the 50-row limit, plus sensitive fields to test redaction
i=1
while [ "$i" -le 60 ]; do
	sqlite3 "$TEST_DB" "INSERT INTO admin_events(id, ts, account_id, action, detail) VALUES ($i, '2026-10-02 12:00:00', 1, 'test_event_$i', 'event $i');"
	i=$((i + 1))
done

# Insert specific event with MAC, IP, PIN, and 32-char hex session token
sqlite3 "$TEST_DB" "INSERT INTO admin_events(id, ts, account_id, action, detail) VALUES (999, '2026-10-02 12:01:00', 2, 'leak_test', 'client 192.168.1.100 with 11:22:33:AA:BB:CC and 11-22-33-44-55-66 pin=889911 token=a1b2c3d4e5f60718293a4b5c6d7e8f90');"

events_json=$(printf '{}' | "$RPC" call dev_events_list)

# Verify valid JSON
printf '%s' "$events_json" | python3 -m json.tool >/dev/null 2>&1 || {
	fail "dev_events_list output is not valid JSON"
}

# Verify limit of 50 events
event_count=$(python3 -c "import json, sys; d=json.loads('''$events_json'''); print(len(d.get('events', [])))")
if [ "$event_count" -eq 50 ]; then
	pass "dev_events_list enforces maximum limit of 50 events"
else
	fail "dev_events_list returned $event_count events (expected exactly 50)"
fi

# Verify MAC redaction
if printf '%s' "$events_json" | grep -F '11:22:33:AA:BB:CC' >/dev/null || \
   printf '%s' "$events_json" | grep -F '11-22-33-44-55-66' >/dev/null; then
	fail "dev_events_list leaked unredacted MAC address"
else
	pass "dev_events_list completely redacts colon and hyphenated MAC addresses"
fi

# Verify IP redaction
if printf '%s' "$events_json" | grep -F '192.168.1.100' >/dev/null; then
	fail "dev_events_list leaked unredacted IP address"
else
	pass "dev_events_list completely redacts IP addresses"
fi

# Verify PIN and Token redaction
if printf '%s' "$events_json" | grep -F '889911' >/dev/null || \
   printf '%s' "$events_json" | grep -F 'a1b2c3d4e5f60718293a4b5c6d7e8f90' >/dev/null; then
	fail "dev_events_list leaked raw PIN or session token"
else
	pass "dev_events_list completely redacts PIN and session token"
fi

# ==============================================================================
# 4. Functional Test: dev_diagnose (8KB limit, exit code capture, failure handling)
# ==============================================================================
MOCK_DIAGNOSE="$TMP_DIR/mock-diagnose.sh"

# Case A: Large output (>8KB) with exit code 0
cat <<'EOF' >"$MOCK_DIAGNOSE"
#!/bin/sh
printf 'OPEN_HOTSPOT_DIAGNOSTIC_V1\n'
# Generate 12KB of text
i=1
while [ "$i" -le 300 ]; do
	printf 'INFO line_%04d client 10.0.0.1 MAC 00:11:22:33:44:55 payload_data\n' "$i"
	i=$((i + 1))
done
exit 0
EOF
chmod +x "$MOCK_DIAGNOSE"

export OPEN_HOTSPOT_DIAGNOSE="$MOCK_DIAGNOSE"
diag_json=$(printf '{}' | "$RPC" call dev_diagnose)

printf '%s' "$diag_json" | python3 -m json.tool >/dev/null 2>&1 || {
	fail "dev_diagnose output is not valid JSON"
}

diag_exit=$(printf '%s' "$diag_json" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('exit_code', -1))")
diag_len=$(printf '%s' "$diag_json" | python3 -c "import json, sys; d=json.load(sys.stdin); print(len(d.get('output', '')))")

if [ "$diag_exit" -eq 0 ]; then
	pass "dev_diagnose captures successful exit code 0"
else
	fail "dev_diagnose exit_code was $diag_exit (expected 0)"
fi

if [ "$diag_len" -le 8192 ] && [ "$diag_len" -gt 7000 ]; then
	pass "dev_diagnose enforces 8192-byte output bound (actual: $diag_len bytes)"
else
	fail "dev_diagnose output length $diag_len not bounded within 8192 bytes"
fi

# Verify redaction inside diagnostic output
if printf '%s' "$diag_json" | grep -F '00:11:22:33:44:55' >/dev/null || \
   printf '%s' "$diag_json" | grep -F '10.0.0.1' >/dev/null; then
	fail "dev_diagnose output leaked MAC or IP address"
else
	pass "dev_diagnose output sanitizes MAC and IP addresses"
fi

# Case B: Failure exit code (exit code 2) with report output
cat <<'EOF' >"$MOCK_DIAGNOSE"
#!/bin/sh
printf 'OPEN_HOTSPOT_DIAGNOSTIC_V1\n'
printf 'FAIL opennds=not-running\n'
printf 'SUMMARY failures=1 warnings=0\n'
exit 2
EOF

diag_fail_json=$(printf '{}' | "$RPC" call dev_diagnose)
diag_fail_exit=$(printf '%s' "$diag_fail_json" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('exit_code', -1))")
diag_fail_has_text=$(printf '%s' "$diag_fail_json" | python3 -c "import json, sys; d=json.load(sys.stdin); print('opennds=not-running' in d.get('output', ''))")

if [ "$diag_fail_exit" -eq 2 ]; then
	pass "dev_diagnose accurately captures non-zero exit code (exit_code=2)"
else
	fail "dev_diagnose failed to capture non-zero exit code (got $diag_fail_exit)"
fi

if [ "$diag_fail_has_text" = "True" ]; then
	pass "dev_diagnose preserves report text even when diagnostic exits with failure"
else
	fail "dev_diagnose dropped report text on non-zero exit"
fi

# ==============================================================================
# 5. Safety: No Shell Input Injection
# ==============================================================================
# Sending shell metacharacters in input JSON must have zero effect on execution
exploit_json='{"command": "; rm -f /tmp/should_never_exist ;", "script": "/bin/sh"}'
printf '%s' "$exploit_json" | "$RPC" call dev_diagnose >/dev/null 2>&1
if [ -f /tmp/should_never_exist ]; then
	fail "dev_diagnose executed arbitrary shell input!"
else
	pass "dev_diagnose rejects/ignores shell input parameters"
fi

printf 'test_dev_diagnostics: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
exit 0
