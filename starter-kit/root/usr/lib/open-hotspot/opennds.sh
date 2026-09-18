#!/bin/sh
# opennds.sh — the only non-BinAuth openNDS control adapter.
#
# The target contract is openNDS 10.3.1-r3 on OpenWrt 25.12.5. This is the
# only module that knows the ndsctl argument order and native units. It must
# never be sourced by BinAuth.

OPEN_HOTSPOT_NDSCTL_BIN="${OPEN_HOTSPOT_NDSCTL_BIN:-/usr/bin/ndsctl}"
OPEN_HOTSPOT_NDS_INIT="${OPEN_HOTSPOT_NDS_INIT:-/etc/init.d/opennds}"

_opennds_nonneg_int() {
	case "$1" in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

_opennds_mac() {
	case "$1" in
		[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
		*) return 1 ;;
	esac
}

_opennds_custom() {
	# FAS custom data is URL-escaped before it reaches openNDS. Keep the
	# adapter conservative: no whitespace, quotes, or shell metacharacters.
	case "$1" in
		'') return 0 ;;
		*[!A-Za-z0-9._~%:/+-]*) return 1 ;;
		*) return 0 ;;
	esac
}

_opennds_bytes_to_kb() {
	bytes="$1"
	_opennds_nonneg_int "$bytes" || return 1
	# Native openNDS volume units are kBytes. Round up so a small positive
	# internal byte budget is never converted to the native unlimited value 0.
	[ "$bytes" -eq 0 ] && printf '0\n' || printf '%s\n' $(( (bytes + 1023) / 1024 ))
}

_opennds_seconds_to_minutes() {
	seconds="$1"
	_opennds_nonneg_int "$seconds" || return 1
	# Native session timeout units are minutes. Round up for the same reason as
	# volume conversion; openNDS receives 0 only for an unlimited policy.
	[ "$seconds" -eq 0 ] && printf '0\n' || printf '%s\n' $(( (seconds + 59) / 60 ))
}

opennds_validate_config() {
	[ -x "$OPEN_HOTSPOT_NDSCTL_BIN" ] || return 1
	"$OPEN_HOTSPOT_NDSCTL_BIN" status >/dev/null 2>&1
}

opennds_reload() {
	# Restart through procd, then require ndsctl to report a live daemon. The
	# bounded readiness check avoids claiming success merely because the init
	# script returned while openNDS is still respawning.
	service="$OPEN_HOTSPOT_NDS_INIT"
	[ -x "$service" ] || return 1
	"$service" restart >/dev/null 2>&1 || return 1
	tries=0
	while [ "$tries" -lt 30 ]; do
		if "$OPEN_HOTSPOT_NDSCTL_BIN" status >/dev/null 2>&1; then
			return 0
		fi
		tries=$((tries + 1))
		sleep 1
	done
	return 1
}

opennds_deauth() {
	[ "$#" -eq 1 ] || return 1
	_opennds_mac "$1" || return 1
	"$OPEN_HOTSPOT_NDSCTL_BIN" deauth "$1"
}

# opennds_apply_session_policy <mac> <seconds> <upload_kbps> <download_kbps>
#     <upload_bytes> <download_bytes> [custom]
#
# Target syntax:
#   ndsctl auth mac|ip|token sessiontimeout(minutes) uploadrate(kb/s)
#       downloadrate(kb/s) uploadquota(kB) downloadquota(kB) customstring
opennds_apply_session_policy() {
	[ "$#" -ge 6 ] && [ "$#" -le 7 ] || return 1
	mac="$1"; seconds="$2"; upload_rate="$3"; download_rate="$4"
	upload_bytes="$5"; download_bytes="$6"; custom="${7:-}"
	_opennds_mac "$mac" || return 1
	_opennds_nonneg_int "$seconds" || return 1
	_opennds_nonneg_int "$upload_rate" || return 1
	_opennds_nonneg_int "$download_rate" || return 1
	_opennds_nonneg_int "$upload_bytes" || return 1
	_opennds_nonneg_int "$download_bytes" || return 1
	_opennds_custom "$custom" || return 1

	session_minutes=$(_opennds_seconds_to_minutes "$seconds") || return 1
	upload_quota=$(_opennds_bytes_to_kb "$upload_bytes") || return 1
	download_quota=$(_opennds_bytes_to_kb "$download_bytes") || return 1
	"$OPEN_HOTSPOT_NDSCTL_BIN" auth "$mac" "$session_minutes" "$upload_rate" \
		"$download_rate" "$upload_quota" "$download_quota" "$custom"
}

opennds_live_clients() {
	"$OPEN_HOTSPOT_NDSCTL_BIN" status
}

case "${1:-}" in
	status) opennds_validate_config ;;
	live-clients) opennds_live_clients ;;
	esac
