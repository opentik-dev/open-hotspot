#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
admin="$root/starter-kit/root/usr/lib/open-hotspot/admin.sh"

sh -n "$admin"
grep -F 'PINs are read from' "$admin" >/dev/null
grep -F 'stdin' "$admin" >/dev/null
grep -F 'pin=$(_admin_pin_line)' "$admin" >/dev/null
grep -F 'BEGIN IMMEDIATE' "$admin" >/dev/null
grep -F 'admin_profile_create' "$admin" >/dev/null
grep -F 'admin_account_create' "$admin" >/dev/null
grep -F 'admin_account_set_pin' "$admin" >/dev/null
grep -F 'admin_device_list' "$admin" >/dev/null
grep -F 'admin_device_set_status' "$admin" >/dev/null
grep -F 'admin_device_remove' "$admin" >/dev/null
grep -F 'admin_device_force_deauth' "$admin" >/dev/null
grep -F 'admin_account_status_list' "$admin" >/dev/null
grep -F 'admin_account_renew' "$admin" >/dev/null
grep -F 'admin_device_reassign' "$admin" >/dev/null
grep -F '_admin_device_reassign_fail' "$admin" >/dev/null
grep -F 'device_account_switched' "$admin" >/dev/null
grep -F 'device_switch_denied' "$admin" >/dev/null
grep -F 'max-devices-exceeded' "$admin" >/dev/null
grep -F 'admin_voucher_list' "$admin" >/dev/null
grep -F 'admin_voucher_generate' "$admin" >/dev/null
grep -F 'admin_voucher_revoke' "$admin" >/dev/null
grep -F 'device_removed' "$admin" >/dev/null
grep -F 'device_remove_denied' "$admin" >/dev/null
grep -F 'usage-history' "$admin" >/dev/null
grep -F 'live-session' "$admin" >/dev/null
grep -F 'device-not-found' "$admin" >/dev/null
grep -F 'invalid-id' "$admin" >/dev/null
grep -F 'device-blocked' "$admin" >/dev/null
grep -F 'has_history' "$admin" || grep -F 'usage_events u WHERE u.device_id=d.id' "$admin" >/dev/null
grep -F 'lifecycle_state' "$admin" || grep -F '"historical"' "$admin" >/dev/null
grep -F 'device_name' "$admin" >/dev/null
! grep -Eq 'ndsctl|opennds[[:space:]]+auth|opennds[[:space:]]+deauth' "$admin"
