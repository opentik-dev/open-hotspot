#!/bin/sh
# Build the noarch APK with the exact apk tool shipped in the OpenWrt SDK.
# The generic SDK make target may rebuild unrelated toolchain packages; this
# focused path packages the repository payload and keeps the build reproducible.

set -eu

PROJECT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SDK=${OPEN_HOTSPOT_SDK:-}
if [ -z "$SDK" ]; then
	if [ -d "$PROJECT/.build/sdk-clean" ]; then
		SDK="$PROJECT/.build/sdk-clean"
	elif [ -d "$PROJECT/../sdk-clean" ]; then
		SDK="$PROJECT/../sdk-clean"
	elif [ -d "$PROJECT/../../.build/sdk-clean" ]; then
		SDK="$PROJECT/../../.build/sdk-clean"
	else
		SDK="$PROJECT/.build/sdk-clean"
	fi
fi

APK="$SDK/staging_dir/host/bin/apk"
MKHASH="$SDK/staging_dir/host/bin/mkhash"
RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$PROJECT/starter-kit/Makefile")
VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$PROJECT/starter-kit/Makefile")
[ -n "$RELEASE" ] && [ -n "$VERSION" ]
[ -x "$APK" ] && [ -x "$MKHASH" ]

# Establish deterministic timestamp for reproducible packaging
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
	SOURCE_DATE_EPOCH=$(git -C "$PROJECT" log -1 --format=%ct 2>/dev/null || true)
fi
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
	SOURCE_DATE_EPOCH=$(stat -c %Y "$PROJECT/starter-kit/Makefile" 2>/dev/null || true)
fi
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
	SOURCE_DATE_EPOCH=1759432000
fi
export SOURCE_DATE_EPOCH
export TZ=UTC
export LC_ALL=C

output="$PROJECT/dist/luci-app-open-hotspot-${VERSION}-r${RELEASE}.apk"
build_dir="$PROJECT/.build/dist-r${RELEASE}"
mkdir -p "$PROJECT/.build" "$PROJECT/dist"
mkdir -p "$build_dir"

package_apk() {
	pkg_output="$1"
	root=$(mktemp -d "$PROJECT/.build/apk-root-r${RELEASE}.XXXXXX")
	mkdir -p "$root/usr/lib/lua/luci" "$root/lib/apk/packages"
	cp -a "$PROJECT/starter-kit/luasrc/." "$root/usr/lib/lua/luci/"
	cp -a "$PROJECT/starter-kit/root/." "$root/"
	printf '%s\n' '/etc/config/open-hotspot' > "$root/lib/apk/packages/luci-app-open-hotspot.conffiles"
	"$MKHASH" sha256 "$root/etc/config/open-hotspot" |
		awk '{print "/etc/config/open-hotspot " $1}' > "$root/lib/apk/packages/luci-app-open-hotspot.conffiles_static"
	(cd "$root" && find . -type f,l -printf '/%P\n' | sort) > "$root/lib/apk/packages/luci-app-open-hotspot.list"

	# Normalize permissions and timestamps for reproducibility
	find "$root" -type d -exec chmod 0755 {} +
	find "$root" -type f -exec chmod 0644 {} +
	find "$root/usr/lib/open-hotspot" -type f -name '*.sh' -exec chmod 0755 {} + 2>/dev/null || true
	find "$root/www/cgi-bin" -type f -exec chmod 0755 {} + 2>/dev/null || true
	find "$root/usr/libexec/rpcd" -type f -exec chmod 0755 {} + 2>/dev/null || true
	find "$root/etc/init.d" -type f -exec chmod 0755 {} + 2>/dev/null || true
	find "$root/etc/uci-defaults" -type f -exec chmod 0755 {} + 2>/dev/null || true
	find "$root" -exec touch -hcd "@$SOURCE_DATE_EPOCH" {} +

	"$APK" mkpkg \
		--info "name:luci-app-open-hotspot" \
		--info "version:${VERSION}-r${RELEASE}" \
		--info 'description:LuCI support for Open-HotSpot (openNDS account/quota manager)' \
		--info 'arch:noarch' \
		--info 'license:GPL-2.0-or-later' \
		--info 'origin:feeds/open_hotspot' \
		--info 'maintainer:Open-HotSpot contributors' \
		--info 'depends:opennds sqlite3-cli php8-cgi php8-mod-pdo-sqlite luci-base luci-compat' \
		--script "post-install:$PROJECT/tools/apk-post-install.sh" \
		--script "post-upgrade:$PROJECT/tools/apk-post-install.sh" \
		--files "$root" \
		--output "$pkg_output"

	rm -rf "$root"
}

if [ "${1:-}" = "--verify" ]; then
	temp_a=$(mktemp "$PROJECT/.build/apk-verify-a.XXXXXX")
	temp_b=$(mktemp "$PROJECT/.build/apk-verify-b.XXXXXX")
	trap 'rm -f "$temp_a" "$temp_b"' EXIT

	package_apk "$temp_a"
	sleep 1
	package_apk "$temp_b"

	hash_a=$(sha256sum "$temp_a" | awk '{print $1}')
	hash_b=$(sha256sum "$temp_b" | awk '{print $1}')

	if [ "$hash_a" != "$hash_b" ]; then
		printf 'ERROR: Nondeterministic APK build detected!\nRun A: %s\nRun B: %s\n' "$hash_a" "$hash_b" >&2
		exit 1
	fi

	cp -f "$temp_a" "$output"
	sha256sum "$output" | tee "$build_dir/SHA256SUMS"
	printf 'Deterministic APK verified: %s\n' "$hash_a"
else
	package_apk "$output"
	sha256sum "$output" | tee "$build_dir/SHA256SUMS"
fi
