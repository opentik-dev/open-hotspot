#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
init="$root/starter-kit/root/etc/init.d/open-hotspot"
makefile="$root/starter-kit/Makefile"

sh -n "$init"
grep -Fx 'START=95' "$init" >/dev/null
grep -Fx 'STOP=10' "$init" >/dev/null
grep -F '[ "$secs" -lt 60 ] && secs=60' "$init" >/dev/null
! grep -Eq 'while[[:space:]]+true|while[[:space:]]+:' "$init"
grep -F 'cycle.sh ${CRON_MARK}' "$init" >/dev/null
grep -F 'maintenance.sh ${CRON_MARK}' "$init" >/dev/null

grep -Fx 'LUCI_DEPENDS:=+opennds +sqlite3-cli +php8-cgi +php8-mod-pdo-sqlite +luci-base +luci-compat' "$makefile" >/dev/null
! grep -Eq '^LUCI_DEPENDS:.*dnsmasq-full' "$makefile"
