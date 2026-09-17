#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
command -v php >/dev/null 2>&1 || {
	echo 'SKIP: php is not installed on the host'
	exit 0
}
command -v hexdump >/dev/null 2>&1 || {
	echo 'SKIP: hexdump is not installed on the host'
	exit 0
}

export OPEN_HOTSPOT_PHP_BIN=php
export OPEN_HOTSPOT_PBKDF2_HELPER="$root/starter-kit/root/usr/lib/open-hotspot/pbkdf2.php"
. "$root/starter-kit/root/usr/lib/open-hotspot/pbkdf2.sh"

stored=$(pw_hash '123456' 5000)
pw_verify '123456' "$stored"
if pw_verify '654321' "$stored"; then
	echo 'wrong PIN was accepted' >&2
	exit 1
fi
