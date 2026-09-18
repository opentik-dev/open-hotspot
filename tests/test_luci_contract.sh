#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
controller="$root/starter-kit/luasrc/controller/open-hotspot.lua"
setup="$root/starter-kit/luasrc/model/cbi/open-hotspot/setup.lua"
profiles="$root/starter-kit/luasrc/view/open-hotspot/profiles.htm"
accounts="$root/starter-kit/luasrc/view/open-hotspot/accounts.htm"
devices="$root/starter-kit/luasrc/view/open-hotspot/devices.htm"
vouchers="$root/starter-kit/luasrc/view/open-hotspot/vouchers.htm"
status="$root/starter-kit/luasrc/view/open-hotspot/status.htm"
history="$root/starter-kit/luasrc/view/open-hotspot/history.htm"
templates="$root/starter-kit/luasrc/view/open-hotspot/templates.htm"

[ -f "$controller" ]
[ -f "$setup" ]
[ -f "$profiles" ]
[ -f "$accounts" ]
[ -f "$devices" ]
[ -f "$vouchers" ]
[ -f "$status" ]
[ -f "$history" ]
[ -f "$templates" ]
grep -F 'cbi("open-hotspot/setup")' "$controller" >/dev/null
grep -F 'call("profiles")' "$controller" >/dev/null
grep -F 'call("accounts")' "$controller" >/dev/null
grep -F 'call("devices")' "$controller" >/dev/null
grep -F 'ubus_call("profile_create"' "$controller" >/dev/null
grep -F 'ubus_call("account_create"' "$controller" >/dev/null
grep -F 'dispatcher.context.authsession' "$controller" >/dev/null
grep -F 'acl_depends = { "luci-app-open-hotspot" }' "$controller" >/dev/null
grep -F 'setup_state' "$setup" >/dev/null
grep -F 'local_fas_enabled' "$setup" >/dev/null
grep -F 'dnsmasq' "$setup" >/dev/null
! grep -Eq 'os\.execute|io\.popen|luci\.sys\.exec' "$setup"
grep -F 'name="token"' "$profiles" >/dev/null
grep -F 'name="token"' "$accounts" >/dev/null
grep -F 'name="token"' "$devices" >/dev/null
grep -F 'device_list' "$controller" >/dev/null
grep -F 'device_block' "$controller" >/dev/null
grep -F 'device_remove' "$controller" >/dev/null
grep -F 'call("vouchers")' "$controller" >/dev/null
grep -F 'call("status")' "$controller" >/dev/null
grep -F 'call("history")' "$controller" >/dev/null
grep -F 'call("templates")' "$controller" >/dev/null
grep -F 'voucher_generate' "$controller" >/dev/null
grep -F 'name="token"' "$vouchers" >/dev/null
grep -F 'opennds_live_status' "$status" >/dev/null
grep -F 'Usage history' "$history" >/dev/null
grep -F 'No closed usage sessions yet' "$history" >/dev/null
grep -F 'template_apply' "$controller" >/dev/null
grep -F 'Use template' "$templates" >/dev/null
grep -F 'setup_base' "$setup" >/dev/null
grep -F 'ubus.connect' "$setup" >/dev/null
