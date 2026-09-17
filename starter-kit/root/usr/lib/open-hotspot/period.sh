#!/bin/sh
# period.sh — compute [period_start, period_end) for a profile's
# period_type, as of "now". Sourced by binauth.sh and cycle.sh so both
# agree on period boundaries.
#
# hourly/daily use fixed-length UTC epoch arithmetic. monthly/yearly use the
# target date utility's calendar arithmetic because their lengths vary. The
# caller must treat a non-zero exit as an unavailable period calculation.

# period_bounds <period_type>  -> prints "period_start<TAB>period_end"
# (both ISO-8601 'YYYY-MM-DDTHH:MM:SSZ', UTC-based)
period_bounds() {
	ptype="$1"
	now_epoch=$(date -u +%s)

	case "$ptype" in
	hourly)
		start_epoch=$(( now_epoch - (now_epoch % 3600) ))
		end_epoch=$(( start_epoch + 3600 ))
		start=$(date -u -d "@${start_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || return 1
		end=$(date -u -d "@${end_epoch}"   '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || return 1
		;;
	daily)
		start_epoch=$(( now_epoch - (now_epoch % 86400) ))
		end_epoch=$(( start_epoch + 86400 ))
		start=$(date -u -d "@${start_epoch}" '+%Y-%m-%dT00:00:00Z' 2>/dev/null) || return 1
		end=$(date -u -d "@${end_epoch}"   '+%Y-%m-%dT00:00:00Z' 2>/dev/null) || return 1
		;;
	monthly)
		year=$(date -u +'%Y') || return 1
		month=$(date -u +'%m') || return 1
		month_num=$(printf '%s' "$month" | sed 's/^0//')
		[ -n "$month_num" ] || month_num=0
		if [ "$month_num" -eq 12 ]; then
			next_year=$((year + 1))
			next_month=01
		else
			next_year=$year
			next_month=$(printf '%02d' $((month_num + 1)))
		fi
		start="${year}-${month}-01T00:00:00Z"
		end="${next_year}-${next_month}-01T00:00:00Z"
		;;
	yearly)
		year=$(date -u +'%Y') || return 1
		next_year=$((year + 1))
		start="${year}-01-01T00:00:00Z"
		end="${next_year}-01-01T00:00:00Z"
		;;
	*)  # none / unlimited: one open-ended sentinel period
		start='1970-01-01T00:00:00Z'
		end='9999-12-31T23:59:59Z'
		;;
	esac

	printf '%s\t%s\n' "$start" "$end"
}

# period_window_at <period_type> <epoch>
# -> period_start_iso<TAB>period_end_iso<TAB>period_start_epoch<TAB>period_end_epoch
# Used by accounting so a session can be split without assigning all traffic
# to the period in which the callback happens.
period_window_at() {
	ptype="$1"
	epoch="$2"
	case "$epoch" in ''|*[!0-9]*) return 1 ;; esac

	case "$ptype" in
		hourly)
			start_epoch=$(( epoch - (epoch % 3600) ))
			end_epoch=$(( start_epoch + 3600 ))
			;;
		daily)
			start_epoch=$(( epoch - (epoch % 86400) ))
			end_epoch=$(( start_epoch + 86400 ))
			;;
		monthly)
			year=$(date -u -d "@${epoch}" +'%Y') || return 1
			month=$(date -u -d "@${epoch}" +'%m') || return 1
			month_num=$(printf '%s' "$month" | sed 's/^0//')
			[ -n "$month_num" ] || month_num=0
			if [ "$month_num" -eq 12 ]; then
				next_year=$((year + 1)); next_month=01
			else
				next_year=$year; next_month=$(printf '%02d' $((month_num + 1)))
			fi
			start_epoch=$(date -u -d "${year}-${month}-01 00:00:00" +%s) || return 1
			end_epoch=$(date -u -d "${next_year}-${next_month}-01 00:00:00" +%s) || return 1
			;;
		yearly)
			year=$(date -u -d "@${epoch}" +'%Y') || return 1
			start_epoch=$(date -u -d "${year}-01-01 00:00:00" +%s) || return 1
			end_epoch=$(date -u -d "$((year + 1))-01-01 00:00:00" +%s) || return 1
			;;
		*)
			start_epoch=0
			end_epoch=2147483647
			;;
	esac

	start=$(date -u -d "@${start_epoch}" '+%Y-%m-%dT%H:%M:%SZ') || return 1
	end=$(date -u -d "@${end_epoch}" '+%Y-%m-%dT%H:%M:%SZ') || return 1
	printf '%s\t%s\t%s\t%s\n' "$start" "$end" "$start_epoch" "$end_epoch"
}
