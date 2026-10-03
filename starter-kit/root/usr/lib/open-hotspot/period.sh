#!/bin/sh
# period.sh — calculate local civil-time periods and persist UTC boundaries.
#
# OpenWrt's configured timezone defines the meaning of a day/month/year. The
# resulting boundaries are always emitted as UTC ISO-8601 values so SQLite and
# openNDS callbacks share one durable representation.

_period_timezone() {
	if [ -n "${OPEN_HOTSPOT_TIMEZONE:-}" ]; then
		printf '%s\n' "$OPEN_HOTSPOT_TIMEZONE"
	elif [ -r /etc/TZ ] && [ -s /etc/TZ ]; then
		cat /etc/TZ
	elif command -v uci >/dev/null 2>&1; then
		uci -q get system.@system[0].timezone 2>/dev/null || printf 'UTC\n'
	else
		printf 'UTC\n'
	fi
}

_period_local_date() { TZ="$(_period_timezone)" date -d "@$1" '+%Y-%m-%d' 2>/dev/null; }
_period_local_year() { TZ="$(_period_timezone)" date -d "@$1" '+%Y' 2>/dev/null; }
_period_local_month() { TZ="$(_period_timezone)" date -d "@$1" '+%m' 2>/dev/null; }
_period_local_hour() { TZ="$(_period_timezone)" date -d "@$1" '+%H' 2>/dev/null; }
_period_local_epoch() { TZ="$(_period_timezone)" date -d "$1" '+%s' 2>/dev/null; }
_period_iso_utc() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; }

# BusyBox date accepts "YYYY-MM-DD HH:MM:SS" but not GNU's ISO form with a
# literal T/Z.  Keep the persisted contract ISO-8601 while normalizing only
# at the parser boundary.  This is also the parser used by BinAuth, cycle, and
# reboot restore, so renewed_at cannot move between different time zones.
_period_epoch_utc() {
	value="$1"
	case "$value" in
		[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
			value=$(printf '%s' "$value" | sed 's/T/ /; s/Z$//')
			;;
		*) return 1 ;;
	esac
	date -u -d "$value" '+%s' 2>/dev/null
}

# period_window_at <period_type> <epoch>
# -> period_start_iso<TAB>period_end_iso<TAB>period_start_epoch<TAB>period_end_epoch
period_window_at() {
	ptype="$1"; epoch="$2"
	case "$epoch" in ''|*[!0-9]*) return 1 ;; esac

	case "$ptype" in
		hourly)
			local_date=$(_period_local_date "$epoch") || return 1
			local_hour=$(_period_local_hour "$epoch") || return 1
			start_epoch=$(_period_local_epoch "$local_date $local_hour:00:00") || return 1
			end_epoch=$((start_epoch + 3600))
			;;
		daily)
			local_date=$(_period_local_date "$epoch") || return 1
			start_epoch=$(_period_local_epoch "$local_date 00:00:00") || return 1
			# Find the first UTC instant whose local date changes. Binary search
			# avoids relative-date parsing and remains correct for 23/25-hour DST
			# days and half-hour timezone transitions.
			low="$start_epoch"; high=$((start_epoch + 172800))
			while [ $((high - low)) -gt 1 ]; do
				candidate=$((low + (high - low) / 2))
				if [ "$(_period_local_date "$candidate")" = "$local_date" ]; then
					low="$candidate"
				else
					high="$candidate"
				fi
			done
			end_epoch="$high"
			;;
		monthly)
			year=$(_period_local_year "$epoch") || return 1
			month=$(_period_local_month "$epoch") || return 1
			month_num=$(printf '%s' "$month" | sed 's/^0//')
			[ -n "$month_num" ] || month_num=0
			if [ "$month_num" -eq 12 ]; then
				next_year=$((year + 1)); next_month=01
			else
				next_year=$year; next_month=$(printf '%02d' $((month_num + 1)))
			fi
			start_epoch=$(_period_local_epoch "$year-$month-01 00:00:00") || return 1
			end_epoch=$(_period_local_epoch "$next_year-$next_month-01 00:00:00") || return 1
			;;
		yearly)
			year=$(_period_local_year "$epoch") || return 1
			start_epoch=$(_period_local_epoch "$year-01-01 00:00:00") || return 1
			end_epoch=$(_period_local_epoch "$((year + 1))-01-01 00:00:00") || return 1
			;;
		*)
			start_epoch=0; end_epoch=2147483647
			;;
	esac

	start=$(_period_iso_utc "$start_epoch") || return 1
	end=$(_period_iso_utc "$end_epoch") || return 1
	printf '%s\t%s\t%s\t%s\n' "$start" "$end" "$start_epoch" "$end_epoch"
}

# period_bounds <period_type> -> period_start<TAB>period_end
period_bounds() {
	window=$(period_window_at "$1" "$(date +%s)") || return 1
	printf '%s\t%s\n' "$(printf '%s' "$window" | cut -f1)" "$(printf '%s' "$window" | cut -f2)"
}

# period_window_effective <period_type> <renewed_at> <epoch>
# A renewal starts a fresh quota window inside the router's current calendar
# period. The original calendar end remains authoritative; after rollover the
# normal calendar boundary becomes the effective start again.
period_window_effective() {
	ptype="$1"; renewed_at="${2:-}"; epoch="$3"
	window=$(period_window_at "$ptype" "$epoch") || return 1
	base_start=$(printf '%s' "$window" | cut -f1)
	base_end=$(printf '%s' "$window" | cut -f2)
	base_start_epoch=$(printf '%s' "$window" | cut -f3)
	base_end_epoch=$(printf '%s' "$window" | cut -f4)
	reset_epoch=0
	if [ -n "$renewed_at" ]; then
		reset_epoch=$(_period_epoch_utc "$renewed_at") || return 1
		case "$reset_epoch" in ''|*[!0-9]*) return 1 ;; esac
	fi
	if [ "$reset_epoch" -gt "$base_start_epoch" ] && [ "$reset_epoch" -lt "$base_end_epoch" ]; then
		printf '%s\t%s\t%s\t%s\n' "$(_period_iso_utc "$reset_epoch")" "$base_end" "$reset_epoch" "$base_end_epoch"
	else
		printf '%s\t%s\t%s\t%s\n' "$base_start" "$base_end" "$base_start_epoch" "$base_end_epoch"
	fi
}
