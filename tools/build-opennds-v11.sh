#!/bin/sh
set -eu

PROJECT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK=${OPENNDS_SDK:-}
OUTPUT=${OPENNDS_OUTPUT:-$PROJECT/dist/opennds-v11}
VERSION=11.0.0
SOURCE_URL="https://codeload.github.com/openNDS/openNDS/tar.gz/v${VERSION}"
SOURCE_HASH=33940f8ef52e958cdf37fd49ca20a8140b85a096d529cf4e0122592ac24ced00

if [ -z "$SDK" ] || [ ! -f "$SDK/Makefile" ] || [ ! -f "$SDK/include/toplevel.mk" ]; then
	printf '%s\n' 'Set OPENNDS_SDK to a matching OpenWrt SDK directory.' >&2
	exit 2
fi

if [ ! -f "$SDK/.config" ]; then
	printf '%s\n' "SDK has no .config: $SDK" >&2
	exit 2
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/opennds-v11-build.XXXXXX")
tmp_package="$SDK/package/opennds-v11-$$"
legacy_package="$SDK/feeds/routing/opennds"
cleanup() {
	if [ -d "$tmp/legacy-opennds" ] && [ ! -e "$legacy_package" ]; then
		mkdir -p "$(dirname "$legacy_package")"
		mv "$tmp/legacy-opennds" "$legacy_package"
	fi
	rm -rf "$tmp" "$tmp_package"
}
trap cleanup EXIT INT TERM

if [ -d "$legacy_package" ]; then
	mv "$legacy_package" "$tmp/legacy-opennds"
fi
mkdir -p "$tmp/source" "$tmp_package"
curl -fL --retry 3 "$SOURCE_URL" -o "$tmp/opennds.tar.gz"
actual_hash=$(sha256sum "$tmp/opennds.tar.gz" | awk '{print $1}')
test "$actual_hash" = "$SOURCE_HASH"
tar -xzf "$tmp/opennds.tar.gz" -C "$tmp/source" --strip-components=1
cp -a "$tmp/source/linux_openwrt/opennds/." "$tmp_package/"
sed -i "s|^PKG_HASH:=.*|PKG_HASH:=$SOURCE_HASH|" "$tmp_package/Makefile"
# The v11 source archive expands to `openNDS-<version>` while OpenWrt's
# default package directory is based on the lower-case package name.
# Pin the build directory to the archive's actual root, as the v10 routing
# feed did, so the source Makefile and files are visible to the package step.
sed -i "/^PKG_VERSION:=/a PKG_BUILD_DIR:=\$(BUILD_DIR)/openNDS-\$(PKG_VERSION)" "$tmp_package/Makefile"
# openNDS v11 ships a hand-written top-level Makefile, not an autotools
# project.  The upstream package template still carries the legacy
# PKG_FIXUP:=autoreconf line; applying it removes the usable Makefile and
# leaves OpenWrt with no compile target.  Keep the source build contract
# explicit and use the shipped Makefile directly.
sed -i '/^PKG_FIXUP:=autoreconf$/d' "$tmp_package/Makefile"

# A previous interrupted SDK build can leave OpenWrt's prepare/configure stamp
# without the corresponding source tree.  Clean this temporary package target
# before compiling so the SDK must unpack and prepare the verified archive in
# the current run.
make -C "$SDK" \
	"package/$(basename "$tmp_package")/clean" V=s

make -C "$SDK" \
	CONFIG_PACKAGE_opennds=m \
	"package/$(basename "$tmp_package")/compile" V=s

mkdir -p "$OUTPUT"
found=0
for artifact in "$SDK"/bin/packages/*/*/opennds-${VERSION}-*.apk \
	"$SDK"/bin/packages/*/*/opennds_${VERSION}-*.apk \
	"$SDK"/bin/packages/*/*/opennds-${VERSION}-*.ipk \
	"$SDK"/bin/packages/*/*/opennds_${VERSION}-*.ipk; do
	[ -f "$artifact" ] || continue
	cp -f "$artifact" "$OUTPUT/"
	found=1
done

if [ "$found" -ne 1 ]; then
	printf '%s\n' "No openNDS $VERSION package was produced under $SDK/bin/packages." >&2
	exit 1
fi

printf 'opennds-v11-artifact-dir=%s\n' "$OUTPUT"
find "$OUTPUT" -maxdepth 1 -type f -name "opennds_${VERSION}-*" -exec sha256sum {} \;
