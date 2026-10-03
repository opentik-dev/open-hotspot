#!/bin/sh
set -eu

# test_release_consistency.sh — Contract test to prevent release metadata drift.
#
# Rules:
# 1. starter-kit/Makefile is the single source of truth for PKG_VERSION and PKG_RELEASE.
# 2. Active status documents (docs/project-status.md, docs/current-state.md,
#    docs/release-policy.md) must declare the exact current source candidate from Makefile.
# 3. Exactly one active declaration of the current source candidate is permitted per active doc
#    (no duplicate or conflicting active version definitions).
# 4. Active documents must not declare an older version (e.g. r90, r79) as the current
#    field candidate.
# 5. Historical references in docs/release-history.md and docs/field-evidence-* are preserved
#    and must not trigger failures.

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

MAKEFILE="$PROJECT/starter-kit/Makefile"
if [ ! -f "$MAKEFILE" ]; then
	printf 'FAIL Makefile not found at %s\n' "$MAKEFILE" >&2
	exit 1
fi

PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$MAKEFILE" | tr -d ' \r\n')
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$MAKEFILE" | tr -d ' \r\n')

if [ -z "$PKG_VERSION" ] || [ -z "$PKG_RELEASE" ]; then
	printf 'FAIL Could not parse PKG_VERSION or PKG_RELEASE from Makefile\n' >&2
	exit 1
fi

EXPECTED_REL="r${PKG_RELEASE}"
EXPECTED_FULL="${PKG_VERSION}-${EXPECTED_REL}"
printf 'test_release_consistency: Makefile source of truth is %s\n' "$EXPECTED_FULL"

FAILURES=0
PASSES=0

pass() { PASSES=$((PASSES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$1" >&2; }

# --- Check 1: docs/project-status.md ---
DOC_PS="$PROJECT/docs/project-status.md"
if [ ! -f "$DOC_PS" ]; then
	fail "missing docs/project-status.md"
else
	# Must not have ambiguous legacy single "Product candidate:" header that conflates working-tree and field candidate
	if grep -Eq '^\*\*Product candidate:\*\*' "$DOC_PS"; then
		fail "docs/project-status.md contains legacy ambiguous 'Product candidate:' line; must distinguish last acceptance candidate vs working-tree candidate"
	fi

	# Must have exactly one "Current source candidate" definition
	wt_matches=$(grep -c 'Current source candidate' "$DOC_PS" || true)
	if [ "$wt_matches" -eq 1 ]; then
		val=$(grep 'Current source candidate' "$DOC_PS" | grep -Eo 'r[0-9]+' | head -1 || true)
		if [ "$val" = "$EXPECTED_REL" ]; then
			pass "docs/project-status.md defines current source candidate as $EXPECTED_REL"
		else
			fail "docs/project-status.md declares $val as current source candidate (expected $EXPECTED_REL)"
		fi
	else
		fail "docs/project-status.md has $wt_matches definitions for Current source candidate (expected exactly 1)"
	fi
fi

# --- Check 2: docs/current-state.md ---
DOC_CS="$PROJECT/docs/current-state.md"
if [ ! -f "$DOC_CS" ]; then
	fail "missing docs/current-state.md"
else
	# Baselines table must have exactly one row for Source candidate
	cs_matches=$(grep -c 'Source candidate' "$DOC_CS" || true)
	if [ "$cs_matches" -eq 1 ]; then
		val=$(grep 'Source candidate' "$DOC_CS" | grep -Eo 'r[0-9]+' | head -1 || true)
		if [ "$val" = "$EXPECTED_REL" ]; then
			pass "docs/current-state.md baselines table declares source candidate as $EXPECTED_REL"
		else
			fail "docs/current-state.md baselines table declares $val as source candidate (expected $EXPECTED_REL)"
		fi
	else
		fail "docs/current-state.md has $cs_matches baselines table rows for Source candidate (expected exactly 1)"
	fi
fi

# --- Check 3: docs/release-policy.md ---
DOC_RP="$PROJECT/docs/release-policy.md"
if [ ! -f "$DOC_RP" ]; then
	fail "missing docs/release-policy.md"
else
	rp_matches=$(grep -Ec 'current (working-tree )?source candidate is r' "$DOC_RP" || true)
	if [ "$rp_matches" -eq 1 ]; then
		val=$(grep -E 'current (working-tree )?source candidate is r' "$DOC_RP" | grep -Eo 'r[0-9]+' | head -1 || true)
		if [ "$val" = "$EXPECTED_REL" ]; then
			pass "docs/release-policy.md declares current source version as $EXPECTED_REL"
		else
			fail "docs/release-policy.md declares $val as current field version (expected $EXPECTED_REL)"
		fi
	else
		fail "docs/release-policy.md has $rp_matches occurrences of 'current source candidate is r' (expected exactly 1)"
	fi
fi

# --- Check 4: Guard against older versions declared as working-tree candidate ---
for doc in docs/project-status.md docs/current-state.md docs/release-policy.md; do
	full="$PROJECT/$doc"
	[ -f "$full" ] || continue
	# Ensure active status lines do not reference historical r79 or r90.
	if grep -E 'Current (field|source) candidate.*r(79|90)\b' "$full" >/dev/null 2>&1; then
		fail "$doc declares obsolete release as current candidate"
	fi
	if grep -E 'Current (field|source) candidate.*r(79|90)\b' "$full" >/dev/null 2>&1; then
		fail "$doc baselines declare obsolete release as current candidate"
	fi
done

printf 'test_release_consistency: %d passed, %d failed\n' "$PASSES" "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
	exit 1
fi
exit 0
