#!/bin/sh
set -eu

# test_apk_reproducibility.sh — Verify bit-for-bit reproducible packaging of the APK

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

# Verify that starter-kit/Makefile defines an explicit non-empty PKG_SOURCE_DATE_EPOCH
grep -Eq '^PKG_SOURCE_DATE_EPOCH:=[0-9]+' "$PROJECT/starter-kit/Makefile" || {
	printf '%s\n' "FAIL: starter-kit/Makefile is missing PKG_SOURCE_DATE_EPOCH" >&2
	exit 1
}

# Verify that an externally supplied mismatched SOURCE_DATE_EPOCH is rejected
mismatch_rc=0
mismatch_out=$(SOURCE_DATE_EPOCH=9999999999 sh "$PROJECT/tools/build-apk.sh" 2>&1) || mismatch_rc=$?
if [ "$mismatch_rc" -eq 0 ]; then
	printf '%s\n' "FAIL: build-apk.sh accepted mismatched SOURCE_DATE_EPOCH" >&2
	exit 1
fi
if ! printf '%s\n' "$mismatch_out" | grep -q "does not match PKG_SOURCE_DATE_EPOCH"; then
	printf '%s\n' "FAIL: build-apk.sh error message did not explain mismatch: $mismatch_out" >&2
	exit 1
fi
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

APK="${SDK:-}/staging_dir/host/bin/apk"
if [ -z "$SDK" ] || [ ! -x "$APK" ]; then
	if [ "${OPEN_HOTSPOT_REQUIRE_SDK:-0}" = "1" ]; then
		printf '%s\n' "FAIL: OpenWrt SDK apk tool required but not found at ${APK:-empty}" >&2
		exit 1
	fi
	printf '%s\n' "SKIP: OpenWrt SDK apk tool not found; skipping live build test (not proof of reproducibility)"
	exit 0
fi

# build-apk.sh writes to dist/. Preserve the existing release artifact so a
# reproducibility check for an unreleased working tree cannot replace the
# canonical artifact used by deployment checks.
OUTPUT="$PROJECT/dist/luci-app-open-hotspot-1.2.0-r$(sed -n 's/^PKG_RELEASE:=//p' "$PROJECT/starter-kit/Makefile").apk"
SAVED_OUTPUT=$(mktemp /tmp/oh-apk-output.XXXXXX)
HAD_OUTPUT=0
if [ -f "$OUTPUT" ]; then
	cp -f "$OUTPUT" "$SAVED_OUTPUT"
	HAD_OUTPUT=1
fi
restore_output() {
	if [ "$HAD_OUTPUT" -eq 1 ]; then
		cp -f "$SAVED_OUTPUT" "$OUTPUT"
	else
		rm -f "$OUTPUT"
	fi
	rm -f "$SAVED_OUTPUT"
}
trap restore_output EXIT INT TERM

output=$(OPEN_HOTSPOT_SDK="$SDK" sh "$PROJECT/tools/build-apk.sh" --verify)
if printf '%s\n' "$output" | grep -q "Deterministic APK verified:"; then
	metadata=$(mktemp /tmp/oh-apk-metadata.XXXXXX)
	if ! STAGING_DIR_HOST="$SDK/staging_dir/host" "$APK" adbdump --format yaml "$OUTPUT" > "$metadata"; then
		rm -f "$metadata"
		printf '%s\n' "FAIL: apk adbdump failed" >&2
		exit 1
	fi
	if non_root_owners=$(grep -E '^[[:space:]]*(user|group):' "$metadata" | grep -vE ':[[:space:]]*root$'); then
		printf '%s\n' "FAIL: Package contains non-root file ownership:" >&2
		printf '%s\n' "$non_root_owners" >&2
		rm -f "$metadata"
		exit 1
	fi
	rm -f "$metadata"
	printf '%s\n' "apk-reproducibility-ok (root:root ownership verified)"
	exit 0
else
	printf '%s\n' "FAIL: build-apk.sh --verify did not confirm deterministic build" >&2
	exit 1
fi
