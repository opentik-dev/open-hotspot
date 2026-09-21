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

# openNDS 11's ndscfg wrapper treats a non-tty stdin as a pipe and can discard
# command-line arguments.  In binauth_log.sh that makes the documented
# custombinauth lookup return empty, so the manager callback is silently
# skipped while openNDS still allows the client.  Keep the stock dispatcher
# and restore path, but provide a UCI fallback for this one include hook.
patch_opennds_custom_binauth() {
	script=/usr/lib/opennds/binauth_log.sh
	backup=/etc/open-hotspot/binauth_log.before-custom-fallback
	[ -r "$script" ] || return 0
	grep -F 'custombinauthpath=$(uci -q get opennds.@opennds[0].custombinauth' "$script" >/dev/null 2>&1 && return 0
	grep -F 'custombinauthpath=$(ndscfg get_option_from_config custombinauth 2> /dev/null)' "$script" >/dev/null 2>&1 || return 0
	mkdir -p /etc/open-hotspot || return 0
	[ -e "$backup" ] || cp -p "$script" "$backup" || return 0
	sed -i 's|^custombinauthpath=$(ndscfg get_option_from_config custombinauth 2> /dev/null)$|custombinauthpath=$(ndscfg get_option_from_config custombinauth 2> /dev/null); if [ -z "$custombinauthpath" ]; then custombinauthpath=$(uci -q get opennds.@opennds[0].custombinauth 2> /dev/null); fi|' "$script"
}

patch_opennds_custom_binauth

# A live upgrade can find a router where local FAS is already enabled but the
# manager init service was never enabled (for example, an older package or a
# factory-reset image). Repair that operational boundary without enabling the
# service in an offline image root.
if [ -z "${IPKG_INSTROOT:-}" ] &&
	[ "$(uci -q get open-hotspot.global.local_fas_enabled 2>/dev/null || true)" = 1 ] &&
	[ -x /etc/init.d/open-hotspot ]; then
	/etc/init.d/open-hotspot enable >/dev/null 2>&1 || true
	/etc/init.d/open-hotspot start >/tmp/open-hotspot-service-start.log 2>&1 || true
fi

# Do not restart an already-running openNDS/open-hotspot stack during an APK
# upgrade. The package may be installed while netifd is reloading the
# firewall; a second restart in that window races openNDS's own fwhook and can
# create a respawn loop. The normal init path and the bounded cycle guard own
# readiness recovery after the network settles.

if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
fi

exit 0
