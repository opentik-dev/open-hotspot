#!/bin/sh
set -eu

command -v sqlite3 >/dev/null 2>&1 || {
	echo 'SKIP: sqlite3-cli is not installed on the host'
	exit 0
}

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_HOTSPOT_DB_PATH="$tmp/hotspot.db"
export OPEN_HOTSPOT_SCHEMA_PATH="$root/starter-kit/root/usr/lib/open-hotspot/schema.sql"
export OPEN_HOTSPOT_MIGRATIONS_PATH="$tmp/migrations"
. "$root/starter-kit/root/usr/lib/open-hotspot/db.sh"

db_init
[ "$(db_schema_version)" = '1' ]
db_init
[ "$(sqlite3 "$OPEN_HOTSPOT_DB_PATH" 'SELECT count(*) FROM profiles;')" = '1' ]

sqlite3 "$tmp/legacy.db" 'CREATE TABLE legacy(value TEXT);'
OPEN_HOTSPOT_DB_PATH="$tmp/legacy.db" db_init >/dev/null 2>&1 && {
	echo 'unversioned database was accepted' >&2
	exit 1
}
