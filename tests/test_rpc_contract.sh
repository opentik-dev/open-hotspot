#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
rpc="$root/starter-kit/root/usr/libexec/rpcd/open_hotspot"
acl="$root/starter-kit/root/usr/share/rpcd/acl.d/luci-app-open-hotspot.json"

sh -n "$rpc"
grep -F 'profile_list' "$rpc" >/dev/null
grep -F 'account_set_pin' "$rpc" >/dev/null
grep -F 'device_list' "$rpc" >/dev/null
grep -F 'device_block' "$rpc" >/dev/null
grep -F 'device_remove' "$rpc" >/dev/null
grep -F 'device_force_deauth' "$rpc" >/dev/null
grep -F 'voucher_list' "$rpc" >/dev/null
grep -F 'voucher_generate' "$rpc" >/dev/null
grep -F 'voucher_revoke' "$rpc" >/dev/null
grep -F 'overview' "$rpc" >/dev/null
grep -F 'account_status_list' "$rpc" >/dev/null
grep -F 'account_renew' "$rpc" >/dev/null
grep -F 'device_reassign' "$rpc" >/dev/null
grep -F 'history_list' "$rpc" >/dev/null
grep -F 'setup_base' "$rpc" >/dev/null
grep -F 'router_access_set' "$rpc" >/dev/null
grep -F 'session_restore_set' "$rpc" >/dev/null
grep -F 'session-restore.sh' "$rpc" >/dev/null
grep -F 'json_load "$input"' "$rpc" >/dev/null
grep -F 'printf' "$rpc" | grep -F '"$pin"' >/dev/null
grep -F '"$ADMIN" account-create' "$rpc" >/dev/null
! grep -Eq 'ndsctl|opennds[[:space:]]+auth|opennds[[:space:]]+deauth' "$rpc"
python3 -m json.tool "$acl" >/dev/null
grep -F 'setup_base' "$acl" >/dev/null
grep -F 'device_force_deauth' "$acl" >/dev/null
grep -F 'account_status_list' "$acl" >/dev/null
grep -F 'account_renew' "$acl" >/dev/null
grep -F 'device_reassign' "$acl" >/dev/null
grep -F 'router_access_set' "$acl" >/dev/null
grep -F 'session_restore_set' "$acl" >/dev/null
