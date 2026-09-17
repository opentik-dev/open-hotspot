#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock="$tmp/db.sh"
state="$tmp/consumed"
separator=$(printf '\t')
printf '%s\n' \
	'db_auth_consume() {' \
	"	[ ! -e \"$state\" ] || return 1" \
	"	touch \"$state\"" \
	"	printf '%s\\n' '7${separator}9${separator}1|120|2048|4096|128|1024|2026-09-16T00:00:00Z|2026-09-17T00:00:00Z${separator}0123456789abcdef0123456789abcdef'" \
	'}' >"$mock"

export OPEN_HOTSPOT_DB_HELPER="$mock"
. "$root/starter-kit/root/usr/lib/open-hotspot/binauth.sh"

session_length=0
upload_rate=0
download_rate=0
upload_quota=0
download_quota=0
exitlevel=1
open_hotspot_binauth_apply auth_client AA:BB:CC:DD:EE:FF \
	http://example.test/ test-agent 192.168.70.20 token \
	0123456789abcdef0123456789abcdef
[ "$exitlevel" = 0 ]
[ "$session_length" = 2 ]
[ "$upload_rate" = 128 ]
[ "$download_rate" = 1024 ]
[ "$upload_quota" = 2 ]
[ "$download_quota" = 4 ]

if open_hotspot_binauth_apply auth_client AA:BB:CC:DD:EE:FF user pass redir ua token \
	0123456789abcdef0123456789abcdef; then
	echo 'deprecated auth_client layout was accepted' >&2
	exit 1
fi

if grep -Eq '(^|[[:space:]])ndsctl[[:space:]]' "$root/starter-kit/root/usr/lib/open-hotspot/binauth.sh"; then
	echo 'administrative control call leaked into BinAuth' >&2
	exit 1
fi

. "$root/starter-kit/root/usr/lib/open-hotspot/period.sh"
segments=$(_oh_binauth_segments daily 1789257600 1789347600 3000 2000)
[ "$(printf '%s' "$segments" | awk 'END { print NR }')" = 2 ]
[ "$(printf '%s' "$segments" | awk -F'|' '{s += $3; u += $4; d += $5} END {print s "|" u "|" d}')" = '90000|2000|3000' ]

# Accounting failure during a deauth callback is deliberately non-fatal to
# openNDS. BinAuth must not turn a completed close into a rejection or issue a
# control-plane command that could revoke an unrelated live session.
failure_db="$tmp/failure-db.sh"
printf '%s\n' \
	'db_session_period_type() { return 1; }' >"$failure_db"
export OPEN_HOTSPOT_DB_HELPER="$failure_db"
exitlevel=1
open_hotspot_binauth_apply client_deauth AA:BB:CC:DD:EE:FF 100 200 1789257600 1789257660 token \
	0123456789abcdef0123456789abcdef
[ "$exitlevel" = 0 ]
