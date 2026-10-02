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

output=$(OPEN_HOTSPOT_SDK="$SDK" sh "$PROJECT/tools/build-apk.sh" --verify)
if printf '%s\n' "$output" | grep -q "Deterministic APK verified:"; then
	printf '%s\n' "apk-reproducibility-ok"
	exit 0
else
	printf '%s\n' "FAIL: build-apk.sh --verify did not confirm deterministic build" >&2
	exit 1
fi
