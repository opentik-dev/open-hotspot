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
grep -F 'admin_voucher_list' "$admin" >/dev/null
grep -F 'admin_voucher_generate' "$admin" >/dev/null
grep -F 'admin_voucher_revoke' "$admin" >/dev/null
! grep -Eq 'ndsctl|opennds[[:space:]]+auth|opennds[[:space:]]+deauth' "$admin"
