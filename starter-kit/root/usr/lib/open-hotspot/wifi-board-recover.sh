#!/bin/sh
# wifi-board-recover.sh — recover a corrupt OpenWrt board definition.
#
# This is an explicit repair action. It is not run during package install and
# never replaces wireless/UCI settings. A copy of the invalid board file is
# retained before board_detect regenerates a validated definition.

set -eu

board=/etc/board.json
backup=/etc/board.json.open-hotspot.invalid
generated=/tmp/open-hotspot-board.json.$$

cleanup() {
	rm -f "$generated"
}
trap cleanup EXIT INT TERM

command -v jsonfilter >/dev/null 2>&1 || {
	echo 'wifi_error=jsonfilter-missing' >&2
	exit 1
}
[ -x /bin/board_detect ] || {
	echo 'wifi_error=board-detect-missing' >&2
	exit 1
}
[ -x /sbin/wifi ] || command -v wifi >/dev/null 2>&1 || {
	echo 'wifi_error=wifi-command-missing' >&2
	exit 1
}

if [ -e "$board" ] && [ ! -e "$backup" ]; then
	cp -p "$board" "$backup"
fi

/bin/board_detect "$generated"
jsonfilter -i "$generated" -e '@' >/dev/null 2>&1 || {
	echo 'wifi_error=board-detect-produced-invalid-json' >&2
	exit 1
}

chmod 0644 "$generated"
mv "$generated" "$board"
wifi reload
printf '%s\n' 'wifi_board_json=recovered'
printf '%s\n' 'wifi_reload=requested'
