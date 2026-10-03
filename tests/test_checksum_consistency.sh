#!/bin/sh
set -eu

# test_checksum_consistency.sh — Contract test to prevent package checksum drift across sources.
#
# Requirements:
# 1. docs/delivery-manifest.md declares the authoritative candidate package SHA-256.
# 2. tools/deploy-r92.sh EXPECTED_SHA matches docs/delivery-manifest.md.
# 3. docs/release-history.md current checkpoint and table row match docs/delivery-manifest.md.
# 4. docs/operational-ledger.md candidate entry matches docs/delivery-manifest.md.
# 5. If dist/ package exists, its sha256sum matches docs/delivery-manifest.md.

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

MAKEFILE="$PROJECT/starter-kit/Makefile"
if [ ! -f "$MAKEFILE" ]; then
	printf 'FAIL: Makefile not found at %s\n' "$MAKEFILE" >&2
	exit 1
fi

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$MAKEFILE" | tr -d ' \r\n')
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$MAKEFILE" | tr -d ' \r\n')

if [ -z "$PKG_VERSION" ] || [ -z "$PKG_RELEASE" ]; then
	printf 'FAIL: Could not parse PKG_VERSION or PKG_RELEASE from Makefile\n' >&2
	exit 1
fi

EXPECTED_REL="r${PKG_RELEASE}"
EXPECTED_FULL="${PKG_VERSION}-${EXPECTED_REL}"

FAILURES=0
PASSES=0

pass() { PASSES=$((PASSES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# 1. Extract candidate SHA from docs/delivery-manifest.md
MANIFEST_FILE="$PROJECT/docs/delivery-manifest.md"
if [ ! -f "$MANIFEST_FILE" ]; then
	fail "missing docs/delivery-manifest.md"
	MANIFEST_SHA=""
else
	MANIFEST_SHA=$(sed -n 's/^\*\*SHA-256:\*\*[[:space:]]*`\([a-f0-9]\{64\}\)`.*/\1/p' "$MANIFEST_FILE" | head -n 1)
	if [ -z "$MANIFEST_SHA" ]; then
		fail "docs/delivery-manifest.md: missing or invalid SHA-256 format"
	else
		pass "docs/delivery-manifest.md candidate SHA-256 extracted ($MANIFEST_SHA)"
	fi
fi

# 2. Extract EXPECTED_SHA from tools/deploy-r92.sh
DEPLOY_FILE="$PROJECT/tools/deploy-r92.sh"
if [ ! -f "$DEPLOY_FILE" ]; then
	fail "missing tools/deploy-r92.sh"
else
	DEPLOY_SHA=$(sed -n 's/^EXPECTED_SHA=.*:- *\([a-f0-9]\{64\}\)}.*/\1/p' "$DEPLOY_FILE" | head -n 1)
	if [ -z "$DEPLOY_SHA" ]; then
		fail "tools/deploy-r92.sh: could not extract EXPECTED_SHA fallback"
	elif [ "$DEPLOY_SHA" != "$MANIFEST_SHA" ]; then
		fail "tools/deploy-r92.sh EXPECTED_SHA ($DEPLOY_SHA) does not match delivery manifest ($MANIFEST_SHA)"
	else
		pass "tools/deploy-r92.sh EXPECTED_SHA matches delivery manifest ($DEPLOY_SHA)"
	fi
fi

# 3. Extract SHA from docs/release-history.md (checkpoint and table)
RELHIST_FILE="$PROJECT/docs/release-history.md"
if [ ! -f "$RELHIST_FILE" ]; then
	fail "missing docs/release-history.md"
else
	CHECKPOINT_SHA=$(sed -n '/## Current publish checkpoint/,/## Historical releases/p' "$RELHIST_FILE" | sed -n 's/.*`\([a-f0-9]\{64\}\)`.*/\1/p' | head -n 1)
	if [ -z "$CHECKPOINT_SHA" ]; then
		fail "docs/release-history.md: could not extract candidate artifact checksum from current checkpoint"
	elif [ "$CHECKPOINT_SHA" != "$MANIFEST_SHA" ]; then
		fail "docs/release-history.md checkpoint SHA ($CHECKPOINT_SHA) does not match delivery manifest ($MANIFEST_SHA)"
	else
		pass "docs/release-history.md current checkpoint SHA matches delivery manifest ($CHECKPOINT_SHA)"
	fi

	TABLE_SHA=$(sed -n "s/^|[[:space:]]*${EXPECTED_REL}[[:space:]]*|[[:space:]]*\`\([a-f0-9]\{64\}\)\`[[:space:]]*|.*/\1/p" "$RELHIST_FILE" | head -n 1)
	if [ -z "$TABLE_SHA" ]; then
		fail "docs/release-history.md: could not extract SHA for $EXPECTED_REL from release table"
	elif [ "$TABLE_SHA" != "$MANIFEST_SHA" ]; then
		fail "docs/release-history.md table SHA ($TABLE_SHA) does not match delivery manifest ($MANIFEST_SHA)"
	else
		pass "docs/release-history.md release table SHA matches delivery manifest ($TABLE_SHA)"
	fi
fi

# 4. Extract SHA from docs/operational-ledger.md
LEDGER_FILE="$PROJECT/docs/operational-ledger.md"
if [ ! -f "$LEDGER_FILE" ]; then
	fail "missing docs/operational-ledger.md"
else
	LEDGER_SHA=$(sed -n "s/.*r${PKG_RELEASE} reproducible SHA-256[[:space:]]*\`\([a-f0-9]\{64\}\)\`.*/\1/p" "$LEDGER_FILE" | tail -n 1)
	if [ -z "$LEDGER_SHA" ]; then
		fail "docs/operational-ledger.md: could not extract r${PKG_RELEASE} reproducible SHA-256"
	elif [ "$LEDGER_SHA" != "$MANIFEST_SHA" ]; then
		fail "docs/operational-ledger.md SHA ($LEDGER_SHA) does not match delivery manifest ($MANIFEST_SHA)"
	else
		pass "docs/operational-ledger.md r${PKG_RELEASE} SHA matches delivery manifest ($LEDGER_SHA)"
	fi
fi

# 5. Verify local built package if present
APK_FILE="$PROJECT/dist/luci-app-open-hotspot-${EXPECTED_FULL}.apk"
if [ -f "$APK_FILE" ]; then
	BUILT_SHA=$(sha256sum "$APK_FILE" | awk '{print $1}')
	if [ "$BUILT_SHA" != "$MANIFEST_SHA" ]; then
		fail "Local APK ($APK_FILE) SHA-256 ($BUILT_SHA) does not match delivery manifest ($MANIFEST_SHA)"
	else
		pass "Local APK SHA-256 verified against delivery manifest ($BUILT_SHA)"
	fi
else
	printf 'NOTE: Local APK not present at %s; skipped local file hash verification\n' "$APK_FILE"
fi

printf 'test_checksum_consistency: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
exit 0
