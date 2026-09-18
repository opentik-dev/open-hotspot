#!/bin/sh
# Build the noarch APK with the exact apk tool shipped in the OpenWrt SDK.
# The generic SDK make target may rebuild unrelated toolchain packages; this
# focused path packages the repository payload and keeps the build reproducible.

set -eu

PROJECT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SDK=${OPEN_HOTSPOT_SDK:-$PROJECT/.build/sdk-clean}
APK="$SDK/staging_dir/host/bin/apk"
MKHASH="$SDK/staging_dir/host/bin/mkhash"
RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$PROJECT/starter-kit/Makefile")
VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$PROJECT/starter-kit/Makefile")
[ -n "$RELEASE" ] && [ -n "$VERSION" ]
[ -x "$APK" ] && [ -x "$MKHASH" ]

output="$PROJECT/dist/luci-app-open-hotspot-${VERSION}-r${RELEASE}.apk"
build_dir="$PROJECT/.build/dist-r${RELEASE}"
root=$(mktemp -d "$PROJECT/.build/apk-root-r${RELEASE}.XXXXXX")
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/usr/lib/lua/luci" "$root/lib/apk/packages" "$build_dir"
cp -a "$PROJECT/starter-kit/luasrc/." "$root/usr/lib/lua/luci/"
cp -a "$PROJECT/starter-kit/root/." "$root/"
printf '%s\n' '/etc/config/open-hotspot' > "$root/lib/apk/packages/luci-app-open-hotspot.conffiles"
"$MKHASH" sha256 "$root/etc/config/open-hotspot" |
	awk '{print "/etc/config/open-hotspot " $1}' > "$root/lib/apk/packages/luci-app-open-hotspot.conffiles_static"
(cd "$root" && find . -type f,l -printf '/%P\n' | sort) > "$root/lib/apk/packages/luci-app-open-hotspot.list"

"$APK" mkpkg \
	--info "name:luci-app-open-hotspot" \
	--info "version:${VERSION}-r${RELEASE}" \
	--info 'description:LuCI support for Open-HotSpot (openNDS account/quota manager)' \
	--info 'arch:noarch' \
	--info 'license:GPL-2.0-or-later' \
	--info 'origin:feeds/open_hotspot' \
	--info 'maintainer:Open-HotSpot contributors' \
	--info 'depends:opennds sqlite3-cli php8-cgi php8-mod-pdo-sqlite luci-base luci-compat' \
	--script "post-install:$PROJECT/.build/apk-post-install" \
	--files "$root" \
	--output "$output"

sha256sum "$output" | tee "$build_dir/SHA256SUMS"
