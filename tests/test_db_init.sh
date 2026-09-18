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
[ "$(db_schema_version)" = '3' ]
db_init
[ "$(sqlite3 "$OPEN_HOTSPOT_DB_PATH" 'SELECT count(*) FROM profiles;')" = '1' ]

sqlite3 "$tmp/legacy.db" 'CREATE TABLE legacy(value TEXT);'
OPEN_HOTSPOT_DB_PATH="$tmp/legacy.db" db_init >/dev/null 2>&1 && {
	echo 'unversioned database was accepted' >&2
	exit 1
}

# A versioned v1 database must take the real numbered migration path. Keep the
# fixture intentionally small: migration 002 only depends on schema_meta and
# accounts, which makes this a useful upgrade-contract test rather than a
# copy of the current schema.
sqlite3 "$tmp/v1.db" <<'SQL'
CREATE TABLE schema_meta (version INTEGER PRIMARY KEY);
INSERT INTO schema_meta(version) VALUES (1);
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,
    pin_hash TEXT NOT NULL,
    pin_salt TEXT NOT NULL,
    pin_iter INTEGER NOT NULL,
    profile_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    expires_at TEXT,
    deleted_at TEXT
);
CREATE TABLE active_sessions (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL,
    device_id INTEGER NOT NULL,
    session_key TEXT NOT NULL,
    started_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    state TEXT NOT NULL
);
SQL
DB_PATH="$tmp/v1.db" db_init
[ "$(DB_PATH="$tmp/v1.db" db_schema_version)" = '3' ]
[ "$(sqlite3 "$tmp/v1.db" "SELECT count(*) FROM pragma_table_info('accounts') WHERE name IN ('failed_attempts','last_failed_at','lock_until');")" = '3' ]
[ "$(sqlite3 "$tmp/v1.db" "SELECT count(*) FROM pragma_table_info('active_sessions') WHERE name='policy_period_start';")" = '1' ]
