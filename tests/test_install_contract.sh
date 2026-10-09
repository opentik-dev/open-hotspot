#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
init="$root/starter-kit/root/etc/init.d/open-hotspot"
makefile="$root/starter-kit/Makefile"
builder="$root/tools/build-apk.sh"
postinstall="$root/tools/apk-post-install.sh"
router_access="$root/starter-kit/root/usr/lib/open-hotspot/router-access.sh"
diagnostics="$root/starter-kit/root/usr/lib/open-hotspot/diagnose.sh"
dnsmasq_capability="$root/starter-kit/root/usr/lib/open-hotspot/dnsmasq-capability.sh"
wifi_recover="$root/starter-kit/root/usr/lib/open-hotspot/wifi-board-recover.sh"
reauth_bridge="$root/starter-kit/root/usr/check_reauth_interval.sh"
network_audit="$root/starter-kit/root/usr/lib/open-hotspot/network-audit.sh"

sh -n "$init"
sh -n "$builder"
sh -n "$postinstall"
sh -n "$router_access"
sh -n "$diagnostics"
sh -n "$dnsmasq_capability"
sh -n "$wifi_recover"
sh -n "$reauth_bridge"
sh -n "$network_audit"
[ -x "$reauth_bridge" ]
grep -Fx 'START=95' "$init" >/dev/null
grep -Fx 'STOP=10' "$init" >/dev/null
grep -F '[ "$secs" -lt 60 ] && secs=60' "$init" >/dev/null
! grep -Eq 'while[[:space:]]+true|while[[:space:]]+:' "$init"
grep -F 'cycle.sh ${CRON_MARK}' "$init" >/dev/null
grep -F 'maintenance.sh ${CRON_MARK}' "$init" >/dev/null
grep -F 'db_init' "$init" >/dev/null
grep -F "DATABASE_FAILED" "$init" >/dev/null

grep -Fx 'LUCI_DEPENDS:=+opennds +sqlite3-cli +php8-cgi +php8-mod-pdo-sqlite +luci-base +luci-compat' "$makefile" >/dev/null
! grep -Eq '^LUCI_DEPENDS:.*dnsmasq-full' "$makefile"
grep -F 'staging_dir/host/bin/apk' "$builder" >/dev/null
grep -F 'tools/apk-post-install.sh' "$builder" >/dev/null
grep -F 'post-install:$PROJECT/tools/apk-post-install.sh' "$builder" >/dev/null
grep -F 'post-upgrade:$PROJECT/tools/apk-post-install.sh' "$builder" >/dev/null
grep -F 'setup.sh base' "$postinstall" >/dev/null
grep -F 'Do not restart an already-running openNDS' "$postinstall" >/dev/null
grep -F 'patch_opennds_procd_stdout' "$postinstall" >/dev/null
grep -F 'procd_set_param stdout 1' "$postinstall" >/dev/null
grep -F 'patch_opennds_custom_binauth' "$postinstall" >/dev/null
grep -F 'opennds.@opennds[0].custombinauth' "$postinstall" >/dev/null
grep -F 'patch_opennds_reauth_helper' "$postinstall" >/dev/null
grep -F 'check_reauth_interval.before-compat' "$postinstall" >/dev/null
grep -F 'If [ -z "$reauth_interval" ]' "$postinstall" >/dev/null
grep -F 'open-hotspot enable' "$postinstall" >/dev/null
grep -F 'open-hotspot start' "$postinstall" >/dev/null
grep -F 'pidof opennds' "$root/starter-kit/root/usr/lib/open-hotspot/opennds.sh" >/dev/null
grep -F 'opennds_wait_ready' "$root/starter-kit/root/etc/init.d/open-hotspot" >/dev/null
grep -F 'ensure_opennds_runtime' "$root/starter-kit/root/usr/lib/open-hotspot/cycle.sh" >/dev/null
grep -F 'open_hotspot_clients' "$router_access" >/dev/null
grep -F 'open_hotspot_deny_router_admin' "$router_access" >/dev/null
grep -F 'open_hotspot_clients_to_wan' "$router_access" >/dev/null
grep -F '22 80 443' "$router_access" >/dev/null
grep -F 'client network must be isolated' "$router_access" >/dev/null
grep -F 'network-audit.sh' "$root/docs/network-service-access-runbook.md" >/dev/null
grep -F 'OPEN_HOTSPOT_DIAGNOSTIC_V1' "$diagnostics" >/dev/null
grep -F 'dnsmasq-full-required-for-autonomous-lists' "$dnsmasq_capability" >/dev/null
grep -F 'apk add dnsmasq-full' "$dnsmasq_capability" >/dev/null
grep -F 'opkg install dnsmasq-full' "$dnsmasq_capability" >/dev/null
grep -F 'board_detect "$generated"' "$wifi_recover" >/dev/null
grep -F 'board-json-invalid' "$root/starter-kit/root/usr/lib/open-hotspot/preflight.sh" >/dev/null
grep -F '. /usr/lib/opennds/check_reauth_interval.sh "$@"' "$reauth_bridge" >/dev/null
! grep -F 'exec /usr/lib/opennds/check_reauth_interval.sh "$@"' "$reauth_bridge" >/dev/null

version=$(sed -n 's/^PKG_VERSION:=//p' "$root/starter-kit/Makefile")
release=$(sed -n 's/^PKG_RELEASE:=//p' "$root/starter-kit/Makefile")
apk_path="$root/dist/luci-app-open-hotspot-${version}-r${release}.apk"
first_sum=$(mktemp)
second_sum=$(mktemp)
trap 'rm -f "$first_sum" "$second_sum"' EXIT
sh "$builder" >/dev/null
sha256sum "$apk_path" | awk '{print $1}' > "$first_sum"
sh "$builder" >/dev/null
sha256sum "$apk_path" | awk '{print $1}' > "$second_sum"
[ "$(cat "$first_sum")" = "$(cat "$second_sum")" ]
