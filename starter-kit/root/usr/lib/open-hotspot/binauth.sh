#!/bin/sh
# binauth.sh — source-safe OpenNDS callback adapter.
#
# This file is sourced by custombinauth.sh after the stock openNDS BinAuth
# logger has initialized session_length/rate/quota/exitlevel. It contains no
# administrative control calls. The target v10.3.1 callback has two layouts:
# auth_client receives MAC, origin URL, user agent, client IP, token, and
# custom data; other reasons receive MAC, counters, session times, token, and
# custom data. Keep the parsers separate instead of guessing from field types.

_oh_binauth_int() {
	case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

_oh_binauth_mac() {
	case "$1" in
		[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
		*) return 1 ;;
	esac
}

_oh_binauth_token() {
	case "$1" in
		''|*[!A-Za-z0-9._~%:/+-]*) return 1 ;;
		*) return 0 ;;
	esac
}

_oh_binauth_key() {
	[ "${#1}" -eq 32 ] || return 1
	case "$1" in *[!0-9A-Fa-f]*) return 1 ;; *) return 0 ;; esac
}

_oh_binauth_policy() {
	snapshot="$1"
	old_ifs="$IFS"
	IFS='|'
	read -r profile_id remaining_time remaining_up remaining_down upload_rate \
		download_rate period_start period_end <<EOF
$snapshot
EOF
	IFS="$old_ifs"
	_oh_binauth_int "$profile_id" || return 1
	_oh_binauth_int "$remaining_time" || return 1
	_oh_binauth_int "$remaining_up" || return 1
	_oh_binauth_int "$remaining_down" || return 1
	_oh_binauth_int "$upload_rate" || return 1
	_oh_binauth_int "$download_rate" || return 1
	case "$period_start:$period_end" in
		*[!0-9TZ:.-]*) return 1 ;;
		*) : ;;
	esac
	[ -n "$period_start" ] && [ -n "$period_end" ] || return 1

	# openNDS native units are minutes, kbit/s, and kBytes. Round positive
	# internal values upward; zero remains the documented unlimited value.
	if [ "$remaining_time" -eq 0 ]; then
		session_length=0
	else
		session_length=$(( (remaining_time + 59) / 60 ))
	fi
	upload_rate="$upload_rate"
	download_rate="$download_rate"
	if [ "$remaining_up" -eq 0 ]; then upload_quota=0; else upload_quota=$(( (remaining_up + 1023) / 1024 )); fi
	if [ "$remaining_down" -eq 0 ]; then download_quota=0; else download_quota=$(( (remaining_down + 1023) / 1024 )); fi
}

open_hotspot_binauth_auth() {
	method="$1"
	[ "$#" -eq 7 ] || return 1
	case "$method" in auth_client) ;; *) return 1 ;; esac
	mac="$2"; token="$6"; custom="$7"
	_oh_binauth_mac "$mac" || return 1
	started=$(date -u +%s) || return 1
	_oh_binauth_int "$started" || return 1
	_oh_binauth_token "$token" || return 1
	_oh_binauth_key "$custom" || return 1

	. "${OPEN_HOTSPOT_DB_HELPER:-/usr/lib/open-hotspot/db.sh}"
	row=$(db_auth_consume "$custom" "$mac" "$started") || return 1
	separator=$(printf '\t')
	old_ifs="$IFS"
	IFS="$separator"
	read -r account_id device_id snapshot consumed_key <<EOF
$row
EOF
	IFS="$old_ifs"
	_oh_binauth_int "$account_id" || return 1
	_oh_binauth_int "$device_id" || return 1
	[ "$consumed_key" = "$custom" ] || return 1
	_oh_binauth_policy "$snapshot" || return 1
	return 0
}

_oh_binauth_segments() {
	period_type="$1"; session_start="$2"; session_end="$3"
	total_in="$4"; total_out="$5"
	[ "$session_end" -ge "$session_start" ] || return 1
	if [ "$session_end" -eq "$session_start" ]; then
		window=$(period_window_at "$period_type" "$session_start") || return 1
		printf '%s|%s|0|0|0\n' "$(printf '%s' "$window" | cut -f1)" "$(printf '%s' "$window" | cut -f2)"
		return 0
	fi

	total_seconds=$((session_end - session_start))
	cursor="$session_start"
	remaining_in="$total_in"
	remaining_out="$total_out"
	newline='
'
	segments=''
	while [ "$cursor" -lt "$session_end" ]; do
		window=$(period_window_at "$period_type" "$cursor") || return 1
		period_start=$(printf '%s' "$window" | cut -f1)
		period_end=$(printf '%s' "$window" | cut -f2)
		period_end_epoch=$(printf '%s' "$window" | cut -f4)
		segment_end="$period_end_epoch"
		[ "$segment_end" -gt "$session_end" ] && segment_end="$session_end"
		segment_seconds=$((segment_end - cursor))
		[ "$segment_seconds" -gt 0 ] || return 1
		if [ "$segment_end" -eq "$session_end" ]; then
			segment_in="$remaining_in"
			segment_out="$remaining_out"
		else
			segment_in=$((total_in * segment_seconds / total_seconds))
			segment_out=$((total_out * segment_seconds / total_seconds))
			remaining_in=$((remaining_in - segment_in))
			remaining_out=$((remaining_out - segment_out))
		fi
		segments="${segments}${period_start}|${period_end}|${segment_seconds}|${segment_out}|${segment_in}${newline}"
		cursor="$segment_end"
	done
	printf '%s' "$segments"
}

open_hotspot_binauth_close() {
	method="$1"; mac="$2"; incoming="$3"; outgoing="$4"
	started="$5"; ended="$6"; token="$7"; custom="$8"
	case "$method" in
		client_deauth|idle_deauth|timeout_deauth|downquota_deauth|upquota_deauth|ndsctl_deauth|shutdown_deauth) ;;
		*) return 1 ;;
	esac
	_oh_binauth_mac "$mac" || return 1
	_oh_binauth_int "$incoming" || return 1
	_oh_binauth_int "$outgoing" || return 1
	_oh_binauth_int "$started" || return 1
	_oh_binauth_int "$ended" || return 1
	[ "$ended" -ge "$started" ] || return 1
	_oh_binauth_token "$token" || return 1
	_oh_binauth_key "$custom" || return 1

	. "${OPEN_HOTSPOT_DB_HELPER:-/usr/lib/open-hotspot/db.sh}"
	. "${OPEN_HOTSPOT_PERIOD_HELPER:-/usr/lib/open-hotspot/period.sh}"
	period_type=$(db_session_period_type "$custom" "$mac") || return 1
	[ -n "$period_type" ] || return 1
	segments=$(_oh_binauth_segments "$period_type" "$started" "$ended" "$incoming" "$outgoing") || return 1
	db_session_close "$method" "$mac" "$custom" "$incoming" "$outgoing" \
		"$started" "$ended" "$segments"
}

open_hotspot_binauth_apply() {
	method="$1"
	case "$method" in
		auth_client)
			[ "$#" -eq 7 ] || { exitlevel=1; return 1; }
			if open_hotspot_binauth_auth "$@"; then
				exitlevel=0
				return 0
			else
				exitlevel=1
				return 1
			fi
			;;
		client_auth)
			# This is the post-authorization observation event. The auth_client
			# callback already consumed the one-time context and set the policy.
			[ "$#" -eq 8 ] || { exitlevel=1; return 1; }
			exitlevel=0
			;;
		client_deauth|idle_deauth|timeout_deauth|downquota_deauth|upquota_deauth|ndsctl_deauth|shutdown_deauth)
			[ "$#" -eq 8 ] || { exitlevel=1; return 1; }
			# Accounting failure must never turn a completed deauthentication into
			# an authentication failure or revoke an unrelated live session.
			open_hotspot_binauth_close "$@" >/dev/null 2>&1 || true
			exitlevel=0
			;;
		*) exitlevel=1; return 1 ;;
	esac
	return 0
}
