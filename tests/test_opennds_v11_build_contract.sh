#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$ROOT/tools/build-opennds-v11.sh"
docs="$ROOT/docs/opennds-v11-build.md"

grep -F 'VERSION=11.0.0' "$script" >/dev/null
grep -F 'SOURCE_HASH=33940f8ef52e958cdf37fd49ca20a8140b85a096d529cf4e0122592ac24ced00' "$script" >/dev/null
grep -F 'arm_cortex-a7_neon-vfpv4' "$docs" >/dev/null
grep -F 'ipq40xx/generic' "$docs" >/dev/null
grep -F 'aarch64_cortex-a53' "$docs" >/dev/null
grep -F 'package/opennds-v11' "$script" >/dev/null
grep -F 'PKG_FIXUP:=autoreconf' "$script" >/dev/null
grep -F 'PKG_BUILD_DIR:=' "$script" >/dev/null
grep -F 'CONFIG_PACKAGE_opennds=m' "$script" >/dev/null
grep -F 'opennds-${VERSION}-*.apk' "$script" >/dev/null

printf '%s\n' 'opennds-v11-build-contract-ok'
