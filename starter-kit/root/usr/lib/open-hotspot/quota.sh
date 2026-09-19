#!/bin/sh
# quota.sh — pure quota arithmetic for domain tests and auth policy code.
# Arguments: limit_seconds used_seconds limit_up_bytes used_up_bytes
#            limit_down_bytes used_down_bytes
# Output: remaining_seconds|remaining_up|remaining_down|exhausted
# A zero limit means unlimited and is represented as zero remaining.

_quota_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

quota_remaining() {
	[ "$#" -eq 6 ] || return 1
	for value in "$@"; do _quota_int "$value" || return 1; done

	limit_s="$1"; used_s="$2"; limit_up="$3"; used_up="$4"; limit_down="$5"; used_down="$6"
	remaining_s=0; remaining_up=0; remaining_down=0; exhausted=0
	if [ "$limit_s" -gt 0 ]; then
		remaining_s=$(( limit_s > used_s ? limit_s - used_s : 0 ))
		[ "$remaining_s" -gt 0 ] || exhausted=1
	fi
	if [ "$limit_up" -gt 0 ]; then
		remaining_up=$(( limit_up > used_up ? limit_up - used_up : 0 ))
		[ "$remaining_up" -gt 0 ] || exhausted=1
	fi
	if [ "$limit_down" -gt 0 ]; then
		remaining_down=$(( limit_down > used_down ? limit_down - used_down : 0 ))
		[ "$remaining_down" -gt 0 ] || exhausted=1
	fi
	printf '%s|%s|%s|%s\n' "$remaining_s" "$remaining_up" "$remaining_down" "$exhausted"
}
