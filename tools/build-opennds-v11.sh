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

make -C "$SDK" \
	"package/$(basename "$tmp_package")/compile" V=s

mkdir -p "$OUTPUT"
found=0
for artifact in "$SDK"/bin/packages/*/*/opennds_${VERSION}-*.apk \
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
