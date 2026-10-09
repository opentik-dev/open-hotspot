#!/bin/sh
set -eu

controller=starter-kit/luasrc/controller/open-hotspot.lua
profiles=starter-kit/luasrc/view/open-hotspot/profiles.htm
vouchers=starter-kit/luasrc/view/open-hotspot/vouchers.htm

grep -F 'scaled_integer' "$controller" >/dev/null
grep -F 'time_limit_s = scaled_integer' "$controller" >/dev/null
grep -F 'upload_limit_b = scaled_integer' "$controller" >/dev/null
grep -F 'upload_rate_kbps = scaled_integer' "$controller" >/dev/null
grep -F 'validity_seconds = scaled_integer' "$controller" >/dev/null
grep -F 'name="time_unit"' "$profiles" >/dev/null
grep -F 'name="upload_unit"' "$profiles" >/dev/null
grep -F 'name="download_unit"' "$profiles" >/dev/null
grep -F 'name="upload_rate_unit"' "$profiles" >/dev/null
grep -F 'name="download_rate_unit"' "$profiles" >/dev/null
grep -F 'name="validity_unit"' "$vouchers" >/dev/null
printf '%s\n' units-contract-ok
