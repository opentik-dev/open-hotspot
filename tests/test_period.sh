#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/starter-kit/root/usr/lib/open-hotspot/period.sh"

iso='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'

for type in hourly daily monthly yearly none; do
	result=$(period_bounds "$type")
	start=$(printf '%s' "$result" | cut -f1)
	end=$(printf '%s' "$result" | cut -f2)
	printf '%s\n' "$start" | grep -Eq "$iso"
	printf '%s\n' "$end" | grep -Eq "$iso"
	[ "$start" \< "$end" ]
done

hourly=$(period_bounds hourly)
daily=$(period_bounds daily)
[ "$(printf '%s' "$hourly" | cut -c15-16)" = '00' ]
[ "$(printf '%s' "$daily" | cut -c11-20)" = 'T00:00:00Z' ]
