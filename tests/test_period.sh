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

# Asia/Aden is UTC+03:00. Local midnight on 2026-01-02 is 2026-01-01T21:00Z.
aden=$(OPEN_HOTSPOT_TIMEZONE=Asia/Aden period_window_at daily \
	"$(date -u -d '2026-01-01 21:30:00' +%s)")
[ "$(printf '%s' "$aden" | cut -f1)" = '2026-01-01T21:00:00Z' ]
[ "$(printf '%s' "$aden" | cut -f2)" = '2026-01-02T21:00:00Z' ]
