#!/bin/bash
# tools/deploy-r92.sh — Reusable guarded deployment and field acceptance driver.
#
# The historical filename is retained for compatibility. Set
# CANDIDATE_RELEASE and CANDIDATE_SHA256 for a newer candidate; defaults remain
# r100 so the newly built candidate is distinct from the installed r99 field artifact.
#
# Operational requirements:
# 1. Strict bash error handling (set -euo pipefail).
# 2. Local validation of the selected candidate APK: existence, exact expected
#    SHA-256, apk verify, and apk adbdump.
#    Mandatory OpenWrt SDK apk tool validation during deployment mode.
# 3. Read-only pre-mutation inspection of router identity (model, boot slot, openNDS version).
#    opennds -v exit code is captured directly; a non-zero code is tolerated only
#    when the command still reports a parseable OpenNDS version.
#    Target board (EA8300) and boot slot (slot 2) are enforced fail-closed by default.
# 4. Strict fail-closed gate: abort immediately on any preflight or diagnostic failure.
#    Failure parser handles arbitrary failure counts (failures > 0, not just 1-9).
# 5. Complete, transactional rollback backup:
#    - Consistent SQLite snapshot via /usr/lib/open-hotspot/backup.sh export.
#    - Complete code, config, service init, LuCI views, and package metadata archive (no '|| true').
#    - Explicit member verification of all claimed backup components before proceeding.
# 6. Strict fail-closed rollback taxonomy:
#    - Cross-verifies installed Open-HotSpot package version with openNDS daemon version:
#      r60 + openNDS 10.3.x -> r60-opennds10.3-production-baseline
#      r90-r100 + openNDS 11.0.x -> r90-r100-opennds11.0-field-candidate
#    - Rejects and aborts on unknown package version or mismatched openNDS version.
# 7. Exact local and remote SHA-256 validation against documented hash.
# 8. Conditional installation: executed only after every single barrier passes.
# 9. Post-install verification: preflight, diagnose, ndsctl status.
# 10. Field status remains explicitly Pending Hardware Validation.

set -euo pipefail

PROJECT=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CANDIDATE_VERSION="${CANDIDATE_VERSION:-1.2.0}"
CANDIDATE_RELEASE="${CANDIDATE_RELEASE:-100}"
EXPECTED_SHA="${CANDIDATE_SHA256:-bcc0fffff8f71d8c8d60cf27c0310e1b75b3996afead7ba3f0708a78300ccf5a}"
CANDIDATE_LABEL="${CANDIDATE_VERSION}-r${CANDIDATE_RELEASE}"
DEFAULT_APK="$PROJECT/dist/luci-app-open-hotspot-${CANDIDATE_LABEL}.apk"
APK_PATH="${APK_PATH:-}"
CHECK_LOCAL_FLAG=0
ALLOW_UNVERIFIED_TARGET="${ALLOW_UNVERIFIED_TARGET:-0}"
EXPECTED_BOARD="${EXPECTED_BOARD:-Linksys EA8300}"
EXPECTED_SLOT="${EXPECTED_SLOT:-2}"

for arg in "$@"; do
	case "$arg" in
		--check-local)
			CHECK_LOCAL_FLAG=1
			;;
		--allow-unverified-target)
			ALLOW_UNVERIFIED_TARGET=1
			;;
		*)
			if [ -z "$APK_PATH" ]; then
				APK_PATH="$arg"
			fi
			;;
	esac
done

APK_PATH="${APK_PATH:-$DEFAULT_APK}"

# Resolve SDK apk tool if available
SDK=${OPEN_HOTSPOT_SDK:-}
if [ -n "$SDK" ] && [ ! -d "$SDK" ]; then
	if [ -d "$PROJECT/$SDK" ]; then
		SDK="$PROJECT/$SDK"
	elif [ -d "$PROJECT/../$SDK" ]; then
		SDK="$PROJECT/../$SDK"
	elif [ -d "$PROJECT/../../$SDK" ]; then
		SDK="$PROJECT/../../$SDK"
	fi
fi
if [ -z "$SDK" ]; then
	if [ -d "$PROJECT/.build/sdk-clean" ]; then
		SDK="$PROJECT/.build/sdk-clean"
	elif [ -d "$PROJECT/../sdk-clean" ]; then
		SDK="$PROJECT/../sdk-clean"
	elif [ -d "$PROJECT/../../.build/sdk-clean" ]; then
		SDK="$PROJECT/../../.build/sdk-clean"
	fi
fi
APK_BIN="${SDK:-}/staging_dir/host/bin/apk"

# ==============================================================================
# Phase 1: Local Artifact & Integrity Verification
# ==============================================================================
echo "=== [Phase 1/7] Local APK artifact and integrity validation ==="

if [ ! -f "$APK_PATH" ]; then
	echo "FAIL: Specified APK does not exist: $APK_PATH" >&2
	exit 1
fi

LOCAL_SHA=$(sha256sum "$APK_PATH" | awk '{print $1}')
if [ "$LOCAL_SHA" != "$EXPECTED_SHA" ]; then
	echo "FAIL: Local APK checksum does not match expected ${CANDIDATE_LABEL} SHA-256!" >&2
	echo "  Found:    $LOCAL_SHA" >&2
	echo "  Expected: $EXPECTED_SHA" >&2
	exit 1
fi
echo "PASS: Local APK checksum verified: $LOCAL_SHA"

# Enforce mandatory apk tool verification in deployment mode
if [ ! -x "$APK_BIN" ]; then
	if [ "$CHECK_LOCAL_FLAG" -eq 1 ] || [ "${CHECK_LOCAL:-0}" = "1" ]; then
		echo "NOTE: OpenWrt SDK apk tool not found; skipped apk binary parsing in check-local mode"
	else
		echo "FAIL: OpenWrt SDK apk tool is required for deployment verification but not found at ${APK_BIN}" >&2
		exit 1
	fi
else
	"$APK_BIN" --allow-untrusted verify "$APK_PATH" >/dev/null || {
		echo "FAIL: apk --allow-untrusted verify failed on $APK_PATH" >&2
		exit 1
	}
	echo "PASS: apk --allow-untrusted verify passed"

	"$APK_BIN" adbdump "$APK_PATH" >/dev/null || {
		echo "FAIL: apk adbdump failed on $APK_PATH" >&2
		exit 1
	}
	echo "PASS: apk adbdump package structure verified"
fi

# Exit early if invoked in local check mode
if [ "$CHECK_LOCAL_FLAG" -eq 1 ] || [ "${CHECK_LOCAL:-0}" = "1" ]; then
	echo "PASS: Local verification completed successfully."
	exit 0
fi

# ==============================================================================
# Target Connection Settings
# ==============================================================================
ROUTER_IP="${ROUTER_IP:-192.168.50.1}"
ROUTER_USER="${ROUTER_USER:-root}"
SSH_BIN="${SSH_BIN:-ssh}"
SSH_TARGET="${ROUTER_USER}@${ROUTER_IP}"
SSH_CMD=("$SSH_BIN")
if [ "$SSH_BIN" = "ssh" ]; then
	SSH_CMD+=(-o BatchMode=yes -o ConnectTimeout=5)
fi
SSH_CMD+=("$SSH_TARGET")

# ==============================================================================
# Phase 2: Target Identity, Slot, and openNDS Verification
# ==============================================================================
echo "=== [Phase 2/7] Interrogating target identity, boot slot, and openNDS ==="

# Check network connectivity and SSH authentication
if ! "${SSH_CMD[@]}" "true" 2>/dev/null; then
	echo "FAIL: Unable to establish SSH connection to $SSH_TARGET" >&2
	echo "      Verify router power, network route, and SSH authorized keys." >&2
	exit 1
fi

BOARD_NAME=$("${SSH_CMD[@]}" "jsonfilter -i /etc/board.json -e '@.model.name' 2>/dev/null || uname -m")
ACTIVE_SLOT=$("${SSH_CMD[@]}" "fw_printenv boot_part 2>/dev/null || grep -o 'boot_part=[0-9]' /proc/cmdline 2>/dev/null || echo 'unknown'")

# Validate opennds -v while preserving both the actual exit code and output.
OPENNDS_RC=0
OPENNDS_VER=$("${SSH_CMD[@]}" "opennds -v 2>&1") || OPENNDS_RC=$?
if [ "$OPENNDS_RC" -ne 0 ]; then
	# openNDS 11.0.0 on the acceptance router prints a valid version string but
	# returns exit code 1. Do not turn that observed compatibility quirk into a
	# blind success: require a parseable version before continuing.
	if ! printf '%s\n' "$OPENNDS_VER" | grep -qiE 'openNDS([[:space:]]+version)?[[:space:]]+[0-9]+\.[0-9]+'; then
		echo "FAIL: opennds -v command failed on $ROUTER_IP (exit code $OPENNDS_RC) and did not report a parseable version: $OPENNDS_VER" >&2
		exit 1
	fi
	echo "WARN: opennds -v returned exit code $OPENNDS_RC but reported a parseable version; continuing with version compatibility checks." >&2
fi

echo "  Target Board:   $BOARD_NAME"
echo "  Active Slot:    $ACTIVE_SLOT"
echo "  Target openNDS: $OPENNDS_VER"

# Enforce board model fail-closed
if ! echo "$BOARD_NAME" | grep -qiE "$EXPECTED_BOARD"; then
	if [ "$ALLOW_UNVERIFIED_TARGET" -eq 1 ]; then
		echo "WARN: Target board ($BOARD_NAME) does not match expected ($EXPECTED_BOARD), overridden by --allow-unverified-target" >&2
	else
		echo "FAIL: Target board ($BOARD_NAME) does not match expected target ($EXPECTED_BOARD). Aborting." >&2
		exit 1
	fi
fi

# Enforce boot slot fail-closed. Accept the documented fw_printenv form or a
# probe that returns the bare slot number, but never match a digit embedded in
# another slot number.
if ! printf '%s\n' "$ACTIVE_SLOT" | grep -qE "(^|[[:space:]])boot_part=${EXPECTED_SLOT}([[:space:]]|$)" && \
	! printf '%s\n' "$ACTIVE_SLOT" | grep -qE "^${EXPECTED_SLOT}$"; then
	if [ "$ALLOW_UNVERIFIED_TARGET" -eq 1 ]; then
		echo "WARN: Active slot ($ACTIVE_SLOT) does not match expected slot ($EXPECTED_SLOT), overridden by --allow-unverified-target" >&2
	else
		echo "FAIL: Active boot slot ($ACTIVE_SLOT) does not match expected candidate slot ($EXPECTED_SLOT). Aborting." >&2
		exit 1
	fi
fi

if ! echo "$OPENNDS_VER" | grep -qiE 'opennds'; then
	echo "FAIL: openNDS output does not identify as openNDS daemon: $OPENNDS_VER" >&2
	exit 1
fi

# ==============================================================================
# Phase 3: Read-Only Preflight and Diagnostic Evaluation
# ==============================================================================
echo "=== [Phase 3/7] Running read-only preflight and diagnostics ==="

PREFLIGHT_RC=0
PREFLIGHT_OUT=$("${SSH_CMD[@]}" "/usr/lib/open-hotspot/preflight.sh") || PREFLIGHT_RC=$?
echo "$PREFLIGHT_OUT"
if [ "$PREFLIGHT_RC" -ne 0 ] || ! echo "$PREFLIGHT_OUT" | grep -q 'topology=ok'; then
	echo "FAIL: Target preflight failed (exit=$PREFLIGHT_RC) or did not report topology=ok. Aborting before mutation." >&2
	exit 1
fi

DIAG_RC=0
DIAG_OUT=$("${SSH_CMD[@]}" "/usr/lib/open-hotspot/diagnose.sh") || DIAG_RC=$?
echo "$DIAG_OUT"

# Robust parser for arbitrary failure counts (handles 0, 1-9, >=10)
DIAG_FAILURES=$(printf '%s\n' "$DIAG_OUT" | sed -n 's/.*failures=\([0-9][0-9]*\).*/\1/p' | head -n 1)
if [ -z "$DIAG_FAILURES" ]; then
	echo "FAIL: Diagnostic output did not report a failures counter (exit=$DIAG_RC). Aborting." >&2
	exit 1
fi
if [ "$DIAG_RC" -ne 0 ] || [ "$DIAG_FAILURES" -ne 0 ]; then
	echo "FAIL: Target diagnostic reported failure (exit=$DIAG_RC, failures=$DIAG_FAILURES). Aborting before mutation." >&2
	exit 1
fi

# ==============================================================================
# Phase 4: Target Package Inspection & Complete Rollback Backup
# ==============================================================================
echo "=== [Phase 4/7] Target package inspection and complete rollback backup ==="

# Documented query: use the installed version file, the packaged Makefile, or
# an offline APK installed-package query. Never allow package description/size-only
# output to stand in for a version; unknown identity is unsafe because it makes
# the rollback archive unclassifiable.
INSTALLED_VERSION=$("${SSH_CMD[@]}" '
	set -eu
	pkg_version=""
	if [ -r /usr/lib/open-hotspot/open-hotspot.version ]; then
		pkg_version=$(tr -d "\r\n" < /usr/lib/open-hotspot/open-hotspot.version)
	else
		makefile=""
		if [ -r /usr/lib/open-hotspot/Makefile ]; then
			makefile=/usr/lib/open-hotspot/Makefile
		elif [ -r /etc/open-hotspot/Makefile ]; then
			makefile=/etc/open-hotspot/Makefile
		fi
		if [ -n "$makefile" ]; then
			version=$(sed -n "s/^PKG_VERSION:=//p" "$makefile" | head -n 1)
			release=$(sed -n "s/^PKG_RELEASE:=//p" "$makefile" | head -n 1)
			if [ -n "$version" ] && [ -n "$release" ]; then
				pkg_version="${version}-r${release}"
			fi
		elif command -v apk >/dev/null 2>&1; then
			# Use the installed database only; never refresh repositories or
			# consume WAN bandwidth during a deployment preflight.
			pkg_version=$(apk --network=false list --installed luci-app-open-hotspot 2>/dev/null |
				sed -n "s/^luci-app-open-hotspot-\([0-9][^[:space:]]*\).*/\1/p" |
				head -n 1)
		fi
	fi
	if [ -z "$pkg_version" ] && [ -r /lib/apk/db/installed ]; then
		# Last local-only fallback: read the installed APK database directly.
		# This avoids repository indexes when apk list has no matching index.
		in_pkg=0
		while IFS= read -r line; do
			case "$line" in
				P:luci-app-open-hotspot) in_pkg=1 ;;
				P:*) in_pkg=0 ;;
				V:*)
					if [ "$in_pkg" -eq 1 ]; then
						pkg_version=${line#V:}
						break
					fi
					;;
			esac
		done < /lib/apk/db/installed
	fi
	if [ -z "$pkg_version" ]; then
		printf "unknown\n"
	else
		printf "%s\n" "$pkg_version"
	fi
')
echo "  Installed Package Version: $INSTALLED_VERSION"

# Fail-closed cross-verification of installed Open-HotSpot version alongside openNDS version
ROLLBACK_CLASSIFICATION="unknown"
if echo "$INSTALLED_VERSION" | grep -qE "r60($|[^0-9])"; then
	if echo "$OPENNDS_VER" | grep -qE "10\.3(\.[0-9]+)?"; then
		ROLLBACK_CLASSIFICATION="r60-opennds10.3-production-baseline"
	else
		echo "FAIL: Rollback classification rejected: r60 installed but openNDS is not 10.3.x ($OPENNDS_VER). Aborting." >&2
		exit 1
	fi
elif echo "$INSTALLED_VERSION" | grep -qE "r(9[0-9]|100)($|[^0-9])"; then
	if echo "$OPENNDS_VER" | grep -qE "11\.0(\.[0-9]+)?"; then
		ROLLBACK_CLASSIFICATION="r90-r100-opennds11.0-field-candidate"
	else
		echo "FAIL: Rollback classification rejected: r90-r100 installed but openNDS is not 11.0.x ($OPENNDS_VER). Aborting." >&2
		exit 1
	fi
else
	echo "FAIL: Rollback classification rejected: unverified installed package version: '$INSTALLED_VERSION'. Aborting." >&2
	exit 1
fi
echo "  Rollback Classification:  $ROLLBACK_CLASSIFICATION"

# r60 is the preserved rollback baseline and must never be upgraded in place.
# Candidates may only be deployed over the isolated r90-r100/openNDS 11.0.x
# candidate slot.
if [ "$ROLLBACK_CLASSIFICATION" != "r90-r100-opennds11.0-field-candidate" ]; then
	echo "FAIL: ${CANDIDATE_LABEL} deployment is restricted to the r90-r100/openNDS 11.0.x candidate slot; preserve r60 as rollback." >&2
	exit 1
fi

umask 077
BACKUP_DIR="${BACKUP_DIR:-/tmp/open-hotspot-backups/deploy-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$BACKUP_DIR"

# 4a. Transactionally consistent SQLite export via backup.sh export
echo "  Generating consistent SQLite snapshot via /usr/lib/open-hotspot/backup.sh export..."
REMOTE_SQLITE_ARCHIVE=$("${SSH_CMD[@]}" "/usr/lib/open-hotspot/backup.sh export")
if [ -z "$REMOTE_SQLITE_ARCHIVE" ]; then
	echo "FAIL: Remote backup.sh export did not return an archive path" >&2
	exit 1
fi

SQLITE_LOCAL="$BACKUP_DIR/sqlite-export.tar.gz"
"${SSH_CMD[@]}" "cat '$REMOTE_SQLITE_ARCHIVE'" > "$SQLITE_LOCAL"
"${SSH_CMD[@]}" "rm -f '$REMOTE_SQLITE_ARCHIVE'"
chmod 0600 "$SQLITE_LOCAL"
tar -ztvf "$SQLITE_LOCAL" >/dev/null
echo "  SQLite snapshot secured: $SQLITE_LOCAL"

# 4b. Full target rollback archive (configuration, database, runtime code,
# service init, LuCI views, and apk tracking)
# Strict execution: no error suppression, no hidden errors.
ROLLBACK_ARCHIVE="$BACKUP_DIR/router-rollback-${ROLLBACK_CLASSIFICATION}.tar.gz"
echo "  Archiving full router runtime/config/metadata state to $ROLLBACK_ARCHIVE..."

"${SSH_CMD[@]}" '
	set -eu
	set -- \
		/etc/config/open-hotspot \
		/etc/config/opennds \
		/etc/open-hotspot \
		/etc/init.d/open-hotspot \
		/etc/init.d/opennds \
		/usr/lib/open-hotspot \
		/usr/lib/opennds \
		/usr/lib/lua/luci/controller/open-hotspot.lua \
		/usr/lib/lua/luci/view/open-hotspot \
		/lib/apk/packages/luci-app-open-hotspot.*
	for p do
		[ -e "$p" ] || { echo "FAIL: required rollback path is missing: $p" >&2; exit 1; }
	done
	# OpenWrt may remove uci-defaults after first boot, so include it when present.
	[ -e /etc/uci-defaults/40-open-hotspot ] && set -- "$@" /etc/uci-defaults/40-open-hotspot
	tar -czf - "$@"
' > "$ROLLBACK_ARCHIVE"

chmod 0600 "$ROLLBACK_ARCHIVE"

# 4c. Verify backup archive integrity and required components locally
tar -ztvf "$ROLLBACK_ARCHIVE" >/dev/null
ARCHIVE_CONTENTS=$(tar -ztf "$ROLLBACK_ARCHIVE")

REQUIRED_COMPONENTS=(
	"etc/config/open-hotspot"
	"etc/config/opennds"
	"etc/open-hotspot/hotspot.db"
	"etc/init.d/open-hotspot"
	"etc/init.d/opennds"
	"usr/lib/open-hotspot"
	"usr/lib/opennds"
	"usr/lib/lua/luci/controller/open-hotspot.lua"
	"usr/lib/lua/luci/view/open-hotspot"
)

for comp in "${REQUIRED_COMPONENTS[@]}"; do
	if ! printf '%s\n' "$ARCHIVE_CONTENTS" | grep -Eq "^${comp}(/|$)"; then
		echo "FAIL: Rollback archive verification failed; missing component: $comp" >&2
		exit 1
	fi
done

if ! printf '%s\n' "$ARCHIVE_CONTENTS" | grep -Eq '^lib/apk/packages/luci-app-open-hotspot\.'; then
	echo "FAIL: Rollback archive verification failed; APK tracking metadata is missing" >&2
	exit 1
fi

sha256sum "$ROLLBACK_ARCHIVE" > "$ROLLBACK_ARCHIVE.sha256"
chmod 0600 "$ROLLBACK_ARCHIVE.sha256"
echo "PASS: Complete rollback archive verified and secured at $ROLLBACK_ARCHIVE"

# ==============================================================================
# Phase 5: Remote Artifact Transfer and Checksum Validation
# ==============================================================================
echo "=== [Phase 5/7] Transferring ${CANDIDATE_LABEL} APK and verifying remote checksum ==="

REMOTE_APK="/tmp/luci-app-open-hotspot-${CANDIDATE_LABEL}.apk"
cat "$APK_PATH" | "${SSH_CMD[@]}" "cat > '$REMOTE_APK'"

REMOTE_SHA=$("${SSH_CMD[@]}" "sha256sum '$REMOTE_APK'" | awk '{print $1}')
if [ "$REMOTE_SHA" != "$EXPECTED_SHA" ]; then
	echo "FAIL: Remote APK checksum does not match expected SHA-256!" >&2
	echo "  Remote:   $REMOTE_SHA" >&2
	echo "  Expected: $EXPECTED_SHA" >&2
	"${SSH_CMD[@]}" "rm -f '$REMOTE_APK'"
	exit 1
fi
echo "PASS: Remote checksum verified: $REMOTE_SHA"

# ==============================================================================
# Phase 6: Package Installation
# ==============================================================================
echo "=== [Phase 6/7] Installing luci-app-open-hotspot ${CANDIDATE_LABEL} ==="

"${SSH_CMD[@]}" "apk add --allow-untrusted '$REMOTE_APK'"
"${SSH_CMD[@]}" "rm -f '$REMOTE_APK'"
echo "PASS: APK installation completed"

# ==============================================================================
# Phase 7: Post-Install Verification & Acceptance Gate Status
# ==============================================================================
echo "=== [Phase 7/7] Post-install verification and diagnostics ==="

"${SSH_CMD[@]}" "/usr/lib/open-hotspot/preflight.sh"
"${SSH_CMD[@]}" "/usr/lib/open-hotspot/diagnose.sh"
"${SSH_CMD[@]}" "ndsctl status"

cat <<EOF
================================================================================
DEPLOYMENT COMPLETED SUCCESSFULLY
Package: luci-app-open-hotspot ${CANDIDATE_LABEL}
Target:  Router at current management address

ACCEPTANCE STATUS: Pending Hardware Validation

CRITICAL NEXT STEP:
The 3-4 minute client eviction issue (T006 / T086) is NOT closed by package
installation. Execute the field acceptance test:
1. Connect a real client phone (VPN and cellular data strictly disabled).
2. Authenticate through the captive portal.
3. Monitor session continuous traffic for 10 to 15 minutes.
4. Verify SQLite state in /etc/open-hotspot/hotspot.db and ndsctl status.
5. Record sanitized evidence in docs/operational-ledger.md before gate closure.
================================================================================
EOF
