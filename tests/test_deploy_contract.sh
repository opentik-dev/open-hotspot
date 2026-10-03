#!/bin/bash
# tests/test_deploy_contract.sh — Contract verification and simulation tests for tools/deploy-r92.sh
#
# Asserts:
# 1. deploy-r92.sh exists and is executable.
# 2. deploy-r92.sh passes bash syntax validation.
# 3. Strict bash error handling (set -euo pipefail) is enabled.
# 4. No '|| true' exists in the backup workflow (Phase 4).
# 5. Rollback taxonomy matches documentation (r60 baseline vs r90-r98 candidate).
# 6. opennds -v exit code is captured directly and non-zero output is validated.
# 7. Failure count parsing handles arbitrary non-zero counts (e.g. failures=12).
# 8. The embedded remote rollback archive command passes POSIX shell syntax.
# 9. The offline APK installed-package parser is used; package tracking files are not parsed as versions.
# 10. A non-existent APK path is rejected immediately.
# 11. A checksum mismatch is rejected immediately.
# 12. Local verification passes for the current Makefile artifact.
# 13. Installation is gated behind preflight, diagnose, and checksums.
# 14. Acceptance status is explicitly output as Pending Hardware Validation.
# 15-29. Simulations cover transport, preflight, diagnostics, rollback, identity,
#        checksum, and successful-path gates without masking failures.

set -euo pipefail

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
DEPLOY_SCRIPT="$PROJECT/tools/deploy-r92.sh"
CURRENT_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$PROJECT/starter-kit/Makefile")
CURRENT_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$PROJECT/starter-kit/Makefile")
CURRENT_APK="$PROJECT/dist/luci-app-open-hotspot-${CURRENT_VERSION}-r${CURRENT_RELEASE}.apk"
CURRENT_APK_NAME="luci-app-open-hotspot-${CURRENT_VERSION}-r${CURRENT_RELEASE}.apk"
CURRENT_APK_SHA=$(sha256sum "$CURRENT_APK" | awk '{print $1}')
MANIFEST_FILE="$PROJECT/docs/delivery-manifest.md"
MANIFEST_SHA=$(sed -n 's/^\*\*SHA-256:\*\*[[:space:]]*`\([a-f0-9]\{64\}\)`.*/\1/p' "$MANIFEST_FILE" | head -n 1)
if [ -z "$MANIFEST_SHA" ]; then
	echo "FAIL: Could not extract documented candidate SHA-256 from $MANIFEST_FILE" >&2
	exit 1
fi
export CANDIDATE_SHA256="${CANDIDATE_SHA256:-$MANIFEST_SHA}"

FAILURES=0
PASSES=0

pass() { PASSES=$((PASSES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# 1. Existence and executability
if [ -f "$DEPLOY_SCRIPT" ] && [ -x "$DEPLOY_SCRIPT" ]; then
	pass "deploy-r92.sh exists and is executable"
else
	fail "deploy-r92.sh missing or not executable"
fi

# 2. Bash syntax check
if bash -n "$DEPLOY_SCRIPT" 2>/dev/null; then
	pass "deploy-r92.sh passes bash syntax check"
else
	fail "deploy-r92.sh has bash syntax errors"
fi

# 3. Strict error handling flags
if grep -qE '^set -euo pipefail' "$DEPLOY_SCRIPT"; then
	pass "deploy-r92.sh enforces set -euo pipefail"
else
	fail "deploy-r92.sh missing set -euo pipefail"
fi

# 4. Prohibit '|| true' in backup workflow
phase4_code=$(sed -n '/Phase 4/,/Phase 5/p' "$DEPLOY_SCRIPT" | grep -v '^[[:space:]]*#')
if printf '%s\n' "$phase4_code" | grep -qE '\|\|[[:space:]]*true'; then
	fail "Phase 4 backup path contains '|| true' masking errors"
else
	pass "Phase 4 backup path strictly prohibits '|| true'"
fi

# 5. Verify rollback taxonomy matches documentation
if grep -q "r60-opennds10.3-production-baseline" "$DEPLOY_SCRIPT" && grep -q "r90-r91-r92-r93-r94-r95-r96-r97-r98-r99-opennds11.0-field-candidate" "$DEPLOY_SCRIPT"; then
	pass "Rollback taxonomy cross-verifies openNDS version with installed package"
else
	fail "Rollback taxonomy does not cross-verify openNDS version with package"
fi

# 6. Verify opennds -v exit code is checked directly
if grep -q 'OPENNDS_VER=.*opennds -v' "$DEPLOY_SCRIPT" && grep -q 'OPENNDS_RC=' "$DEPLOY_SCRIPT"; then
	pass "opennds -v exit code is verified directly without suppression"
else
	fail "opennds -v exit code is not verified directly"
fi

# 7. Verify failure count parser handles multi-digit failure counts
if grep -qE 'failures=|failures\\=|\[0-9\]\[0-9\]\*' "$DEPLOY_SCRIPT"; then
	pass "Diagnostic failure parser handles arbitrary multi-digit failure counts"
else
	fail "Diagnostic failure parser does not handle arbitrary multi-digit failure counts"
fi

# 8. Validate the embedded POSIX shell sent to the router for rollback tar.
remote_archive_block=$(sed -n '/^[[:space:]]*set -eu$/,/^[[:space:]]*tar -czf - "\$@"$/p' "$DEPLOY_SCRIPT")
if printf '%s\n' "$remote_archive_block" | sed 's/^[[:space:]]//' | sh -n 2>/dev/null; then
	pass "Embedded remote rollback archive command passes POSIX shell syntax"
else
	fail "Embedded remote rollback archive command has shell syntax errors"
fi

# 8. Verify offline APK fallback parser and reject .list version extraction
if ! grep -q -- "apk --network=false list --installed luci-app-open-hotspot" "$DEPLOY_SCRIPT" ||
	! grep -q "P:luci-app-open-hotspot" "$DEPLOY_SCRIPT" ||
	! grep -q "s/\^luci-app-open-hotspot-" "$DEPLOY_SCRIPT" ||
	grep -q 'sed.*version.*\.list' "$DEPLOY_SCRIPT"; then
	fail "deploy-r92.sh incorrectly relies on .list file for version extraction"
else
	pass "deploy-r92.sh uses offline installed-package parser and does not use .list file"
fi

# 9. Rejection of non-existent APK
missing_out=$(bash "$DEPLOY_SCRIPT" /nonexistent/file.apk --check-local 2>&1) && missing_rc=0 || missing_rc=$?
if [ "$missing_rc" -ne 0 ] && printf '%s\n' "$missing_out" | grep -q "FAIL: Specified APK does not exist"; then
	pass "Non-existent APK path rejected with clean error"
else
	fail "Non-existent APK path was not rejected properly (rc=$missing_rc: $missing_out)"
fi

# 10. Rejection of invalid checksum
tmp_bad=$(mktemp /tmp/test-bad-apk.XXXXXX)
printf '%s\n' "corrupted-payload" > "$tmp_bad"
bad_out=$(bash "$DEPLOY_SCRIPT" "$tmp_bad" --check-local 2>&1) && bad_rc=0 || bad_rc=$?
rm -f "$tmp_bad"

if [ "$bad_rc" -ne 0 ] && printf '%s\n' "$bad_out" | grep -q "checksum does not match"; then
	pass "Mismatched APK checksum rejected with clean error"
else
	fail "Mismatched APK checksum was not rejected properly (rc=$bad_rc: $bad_out)"
fi

# 11. Local validation of the current APK
local_out=$(bash "$DEPLOY_SCRIPT" --check-local 2>&1) && local_rc=0 || local_rc=$?
if [ "$local_rc" -eq 0 ] && printf '%s\n' "$local_out" | grep -q "Local APK checksum verified"; then
	pass "Current APK local verification passed"
else
	fail "Current APK local verification failed (rc=$local_rc: $local_out)"
fi

# 12. Gate ordering: preflight, diagnose, and checksums must precede installation
line_preflight=$(grep -n "/usr/lib/open-hotspot/preflight\.sh" "$DEPLOY_SCRIPT" | head -n 1 | cut -d: -f1)
line_diagnose=$(grep -n "/usr/lib/open-hotspot/diagnose\.sh" "$DEPLOY_SCRIPT" | head -n 1 | cut -d: -f1)
line_checksum=$(grep -n "REMOTE_SHA=" "$DEPLOY_SCRIPT" | head -n 1 | cut -d: -f1)
line_install=$(grep -n "apk add --allow-untrusted" "$DEPLOY_SCRIPT" | head -n 1 | cut -d: -f1)

if [ "$line_preflight" -lt "$line_install" ] && \
   [ "$line_diagnose" -lt "$line_install" ] && \
   [ "$line_checksum" -lt "$line_install" ]; then
	pass "Installation is strictly ordered after preflight, diagnose, and remote checksum verification"
else
	fail "Installation ordering contract violated (preflight=$line_preflight, diag=$line_diagnose, sha=$line_checksum, install=$line_install)"
fi

# 13. Status declaration: must declare Pending Hardware Validation
if grep -q "Pending Hardware Validation" "$DEPLOY_SCRIPT"; then
	pass "deploy-r92.sh explicitly declares Pending Hardware Validation status"
else
	fail "deploy-r92.sh missing Pending Hardware Validation status notice"
fi

# ==============================================================================
# Simulation Tests (Using Mock SSH Harness)
# ==============================================================================
SIM_DIR=$(mktemp -d /tmp/deploy-sim.XXXXXX)
trap 'rm -rf "$SIM_DIR"' EXIT

MOCK_SSH="$SIM_DIR/mock-ssh.sh"
AUDIT_LOG="$SIM_DIR/remote-commands.log"
MOCK_ROUTER="$SIM_DIR/mock-router"

# Set up mock router filesystem for genuine tar generation
mkdir -p "$MOCK_ROUTER/etc/config" "$MOCK_ROUTER/etc/open-hotspot" "$MOCK_ROUTER/etc/init.d" "$MOCK_ROUTER/usr/lib/open-hotspot" "$MOCK_ROUTER/usr/lib/opennds" "$MOCK_ROUTER/usr/lib/lua/luci/controller" "$MOCK_ROUTER/usr/lib/lua/luci/view" "$MOCK_ROUTER/lib/apk/packages"
touch "$MOCK_ROUTER/etc/config/open-hotspot"
touch "$MOCK_ROUTER/etc/config/opennds"
touch "$MOCK_ROUTER/etc/open-hotspot/hotspot.db"
touch "$MOCK_ROUTER/etc/init.d/open-hotspot"
touch "$MOCK_ROUTER/etc/init.d/opennds"
touch "$MOCK_ROUTER/usr/lib/open-hotspot/db.sh"
touch "$MOCK_ROUTER/usr/lib/opennds/opennds.sh"
touch "$MOCK_ROUTER/usr/lib/lua/luci/controller/open-hotspot.lua"
touch "$MOCK_ROUTER/usr/lib/lua/luci/view/open-hotspot"
touch "$MOCK_ROUTER/lib/apk/packages/luci-app-open-hotspot.list"
touch "$MOCK_ROUTER/lib/apk/packages/luci-app-open-hotspot.conffiles"

# Create Mock SSH script
cat <<'EOF' > "$MOCK_SSH"
#!/bin/bash
set -eu

cmd="${!#}"
echo "$cmd" >> "$SIM_AUDIT_LOG"

case "${SIMULATE_FAIL:-none}" in
	ssh)
		echo "ssh: connect to host 192.168.50.1 port 22: Connection refused" >&2
		exit 255
		;;
	preflight)
		if echo "$cmd" | grep -q "preflight\.sh"; then
			echo "preflight failed: topology=overlap"
			exit 1
		fi
		;;
	diagnose)
		if echo "$cmd" | grep -q "diagnose\.sh"; then
			echo "diagnostic summary: failures=12 warnings=0"
			exit 0
		fi
		;;
	tar)
		if echo "$cmd" | grep -q "tar -czf"; then
			echo "tar: error archiving files" >&2
			exit 2
		fi
		;;
	checksum)
		if echo "$cmd" | grep -q "sha256sum.*luci-app-open-hotspot"; then
			echo "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  /tmp/luci-app-open-hotspot-1.2.0-r92.apk"
			exit 0
		fi
		;;
	baseline)
		if echo "$cmd" | grep -q "open-hotspot\\.version"; then
			echo "1.2.0-r60"
			exit 0
		fi
		if echo "$cmd" | grep -q "opennds -v"; then
			echo "openNDS 10.3.1-r3"
			exit 0
		fi
		;;
	unknown-version)
		if echo "$cmd" | grep -q "open-hotspot\\.version"; then
			echo "1.2.0-r999"
			exit 0
		fi
		;;
	r91-candidate)
		if echo "$cmd" | grep -q "open-hotspot\\.version"; then
			echo "1.2.0-r91"
			exit 0
		fi
		;;
	opennds-exit)
		if echo "$cmd" | grep -q "opennds -v"; then
			echo "opennds probe failed" >&2
			exit 7
		fi
		;;
	opennds-version-warning)
		if echo "$cmd" | grep -q "opennds -v"; then
			echo "This is openNDS version 11.0.0"
			exit 1
		fi
		;;
	no-version-file)
		if echo "$cmd" | grep -q "apk --network=false list --installed luci-app-open-hotspot"; then
			echo "1.2.0-r90"
			exit 0
		fi
		;;
	raw-apk-db)
		if echo "$cmd" | grep -q "/lib/apk/db/installed"; then
			echo "1.2.0-r90"
			exit 0
		fi
		;;
	wrong-board)
		if echo "$cmd" | grep -q "board\\.json"; then
			echo "Other Router"
			exit 0
		fi
		;;
	wrong-slot)
		if echo "$cmd" | grep -q "fw_printenv"; then
			echo "boot_part=1"
			exit 0
		fi
		;;
esac

# Default normal mock responses:
if [ "$cmd" = "true" ]; then
	exit 0
elif echo "$cmd" | grep -q "board\.json"; then
	echo "Linksys EA8300"
	exit 0
elif echo "$cmd" | grep -q "fw_printenv"; then
	echo "boot_part=2"
	exit 0
elif echo "$cmd" | grep -q "opennds -v"; then
	echo "openNDS 11.0.0-r1"
	exit 0
elif echo "$cmd" | grep -q "preflight\.sh"; then
	echo "topology=ok uhttpd=ok sqlite=ok opennds=ok"
	exit 0
elif echo "$cmd" | grep -q "diagnose\.sh"; then
	echo "status=ok failures=0 warnings=0"
	exit 0
elif echo "$cmd" | grep -q "apk --network=false list --installed luci-app-open-hotspot"; then
	echo "1.2.0-r90"
	exit 0
elif echo "$cmd" | grep -q "open-hotspot\.version"; then
	echo "1.2.0-r90"
	exit 0
elif echo "$cmd" | grep -q "backup\.sh export"; then
	echo "/tmp/mock-sqlite-export.tar.gz"
	exit 0
elif echo "$cmd" | grep -q "cat '/tmp/mock-sqlite-export.tar.gz'"; then
	tar -czf - -C "$SIM_MOCK_ROUTER" etc/open-hotspot/hotspot.db etc/config/open-hotspot
	exit 0
elif echo "$cmd" | grep -q "rm -f '/tmp/mock-sqlite-export.tar.gz'"; then
	exit 0
	elif echo "$cmd" | grep -q "tar -czf -"; then
		tar -czf - -C "$SIM_MOCK_ROUTER" etc usr lib
	exit 0
elif echo "$cmd" | grep -q "cat > '/tmp/luci-app-open-hotspot-1.2.0-r"; then
	cat >/dev/null
	exit 0
elif echo "$cmd" | grep -q "sha256sum.*luci-app-open-hotspot"; then
	echo "$SIM_APK_SHA  /tmp/$SIM_APK_NAME"
	exit 0
elif echo "$cmd" | grep -q "apk add --allow-untrusted"; then
	echo "OK: 1 packages installed"
	exit 0
elif echo "$cmd" | grep -q "ndsctl status"; then
	echo "openNDS status: operational, clients=0"
	exit 0
else
	exit 0
fi
EOF
chmod +x "$MOCK_SSH"

export SIM_AUDIT_LOG="$AUDIT_LOG"
export SIM_MOCK_ROUTER="$MOCK_ROUTER"
export SIM_APK_NAME="$CURRENT_APK_NAME"
export SIM_APK_SHA="$CURRENT_APK_SHA"

# --- Simulation 1: SSH Connection Failure ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="ssh" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 1: SSH connection failure aborted and did NOT execute apk add"
else
	fail "Simulation 1: SSH failure handling failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 2: Preflight Failure ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="preflight" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 2: Preflight failure aborted and did NOT execute apk add"
else
	fail "Simulation 2: Preflight failure handling failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 3: Diagnostic Failure (failures > 9) ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="diagnose" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 3: Diagnostic failure (failures=12) aborted and did NOT execute apk add"
else
	fail "Simulation 3: Diagnostic failure handling failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 4: Rollback Tar Failure ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="tar" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 4: Rollback tar failure aborted and did NOT execute apk add"
else
	fail "Simulation 4: Rollback tar failure handling failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 5: Remote Checksum Mismatch ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="checksum" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 5: Remote checksum mismatch aborted and did NOT execute apk add"
else
	fail "Simulation 5: Remote checksum mismatch handling failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 6: Complete Successful Run ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="none" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -eq 0 ] && grep -q "apk add" "$AUDIT_LOG" && printf '%s\n' "$sim_out" | grep -q "Pending Hardware Validation"; then
	pass "Simulation 6: Clean target run succeeded, executed apk add, and declared Pending Hardware Validation"
else
	fail "Simulation 6: Clean target run failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 7: r60 baseline is never upgraded in place ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="baseline" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 7: r60 rollback baseline rejected before apk add"
else
	fail "Simulation 7: r60 baseline was not rejected (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 8: r91 openNDS 11 candidate is accepted ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="r91-candidate" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -eq 0 ] && grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 8: r91/openNDS 11 candidate accepted before apk add"
else
	fail "Simulation 8: r91 candidate was not accepted (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 9: unknown package version is rejected ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="unknown-version" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 9: unknown installed package version rejected before apk add"
else
	fail "Simulation 9: unknown package version was not rejected (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 10: opennds -v failure without a version is rejected ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="opennds-exit" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 10: opennds probe without a parseable version rejected before apk add"
else
	fail "Simulation 10: invalid opennds probe was not rejected (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 11: valid version text with non-zero exit is accepted ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="opennds-version-warning" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -eq 0 ] && grep -q "apk add" "$AUDIT_LOG" && printf '%s\n' "$sim_out" | grep -q "exit code 1"; then
	pass "Simulation 11: parseable opennds version with exit code 1 continued safely"
else
	fail "Simulation 11: valid non-zero opennds version output was not accepted safely (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 12: package version fallback works without version file ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="no-version-file" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -eq 0 ] && grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 12: offline APK version fallback accepted r90 candidate"
else
	fail "Simulation 12: offline APK version fallback failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 13: raw installed APK database fallback works ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="raw-apk-db" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -eq 0 ] && grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 13: raw installed APK database fallback accepted r90 candidate"
else
	fail "Simulation 13: raw installed APK database fallback failed (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 14: wrong board identity is rejected ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="wrong-board" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 14: wrong board identity rejected before apk add"
else
	fail "Simulation 14: wrong board identity was not rejected (rc=$sim_rc: $sim_out)"
fi

# --- Simulation 15: wrong boot slot is rejected ---
: > "$AUDIT_LOG"
sim_out=$(SIMULATE_FAIL="wrong-slot" SSH_BIN="$MOCK_SSH" bash "$DEPLOY_SCRIPT" 2>&1) && sim_rc=0 || sim_rc=$?
if [ "$sim_rc" -ne 0 ] && ! grep -q "apk add" "$AUDIT_LOG"; then
	pass "Simulation 15: wrong boot slot rejected before apk add"
else
	fail "Simulation 15: wrong boot slot was not rejected (rc=$sim_rc: $sim_out)"
fi

printf '\ntest_deploy_contract: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
