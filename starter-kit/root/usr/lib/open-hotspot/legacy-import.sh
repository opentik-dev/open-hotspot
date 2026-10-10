#!/bin/sh
# Safe importer for the pre-r112 Open-HotSpot database. Default is read-only.
set -eu
mode=dry-run
confirm=
for arg in "$@"; do
	case "$arg" in
		--dry-run) mode=dry-run ;;
		--import) mode=import ;;
		--confirm-legacy-import) confirm=YES ;;
		*) echo "usage: $0 [--dry-run|--import --confirm-legacy-import]" >&2; exit 2 ;;
	esac
done
[ "$mode" = dry-run ] || [ "$confirm" = YES ] || {
	echo "open-hotspot legacy import: explicit confirmation required" >&2
	exit 2
}
PHP_BIN="${OPEN_HOTSPOT_PHP_BIN:-php8-cgi}"
command -v "$PHP_BIN" >/dev/null 2>&1 || PHP_BIN=php-cgi
command -v "$PHP_BIN" >/dev/null 2>&1 || { echo "open-hotspot legacy import: PHP CGI unavailable" >&2; exit 1; }
export OPEN_HOTSPOT_LEGACY_IMPORT_MODE="$mode"
[ "$mode" = dry-run ] || export OPEN_HOTSPOT_LEGACY_IMPORT_CONFIRM=YES
exec "$PHP_BIN" -q -f /usr/lib/open-hotspot/legacy-import.php
