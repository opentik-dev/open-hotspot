#!/bin/sh
set -eu

# test_apk_reproducibility.sh — Verify bit-for-bit reproducible packaging of the APK

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
SDK=${OPEN_HOTSPOT_SDK:-}
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
	printf '%s\n' "SKIP: OpenWrt SDK apk tool not found; skipping live reproducible build test"
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
