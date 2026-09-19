#!/bin/sh

# Do not run target setup while an image is being assembled offline. Some
# live apk installations expose IPKG_INSTROOT as well, so use the installed
# project path to distinguish an image root from the running target.
if [ -n "${IPKG_INSTROOT:-}" ] && [ ! -x /usr/lib/open-hotspot/setup.sh ]; then
	exit 0
fi

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/

# The base boundary is safe to retry and must also run for a package upgrade;
# relying only on /etc/uci-defaults leaves an already-booted factory router
# with a stale setup state.
if [ -x /usr/lib/open-hotspot/setup.sh ]; then
	/usr/lib/open-hotspot/setup.sh base >/tmp/open-hotspot-setup.log 2>&1 || true
fi

# OpenWrt 25.12.5's openNDS 10.3.1 init wrapper forwards stdout to procd.
# On the Linksys EA8300 target that causes the daemon to exit during startup,
# while the same binary is stable when stdout is not redirected. Keep a
# recoverable copy and remove only the exact wrapper line; do not alter the
# openNDS UCI configuration or restart the service during an APK upgrade.
patch_opennds_procd_stdout() {
	init=/etc/init.d/opennds
	backup=/etc/open-hotspot/opennds.init.before-stdout-patch
	[ -r "$init" ] || return 0
	grep -F 'procd_set_param stdout 1' "$init" >/dev/null 2>&1 || return 0
	version=$(/usr/bin/opennds -v 2>/dev/null | sed -n '1p')
	case "$version" in
		*10.3.1*) ;;
		*) return 0 ;;
	esac
	mkdir -p /etc/open-hotspot || return 0
	[ -e "$backup" ] || cp -p "$init" "$backup" || return 0
	sed -i '/^[[:space:]]*procd_set_param stdout 1[[:space:]]*$/d' "$init"
}

patch_opennds_procd_stdout

# Do not restart an already-running openNDS/open-hotspot stack during an APK
# upgrade. The package may be installed while netifd is reloading the
# firewall; a second restart in that window races openNDS's own fwhook and can
# create a respawn loop. The normal init path and the bounded cycle guard own
# readiness recovery after the network settles.

if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
fi

exit 0
