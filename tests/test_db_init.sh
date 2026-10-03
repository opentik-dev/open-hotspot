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
export OPEN_HOTSPOT_MIGRATIONS_PATH="$root/starter-kit/root/usr/lib/open-hotspot/migrations"
. "$root/starter-kit/root/usr/lib/open-hotspot/db.sh"

db_init
[ "$(db_schema_version)" = '5' ]
db_init
[ "$(sqlite3 "$OPEN_HOTSPOT_DB_PATH" 'SELECT count(*) FROM profiles;')" = '1' ]

sqlite3 "$tmp/legacy.db" 'CREATE TABLE legacy(value TEXT);'
DB_PATH="$tmp/legacy.db" db_init >/dev/null 2>&1 && {
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
CREATE TABLE auth_transactions (
    id INTEGER PRIMARY KEY,
    auth_key TEXT NOT NULL UNIQUE,
    account_id INTEGER NOT NULL,
    device_mac TEXT NOT NULL,
    profile_id INTEGER NOT NULL,
    policy_snapshot TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    consumed_at TEXT,
    state TEXT NOT NULL
);
SQL
DB_PATH="$tmp/v1.db" db_init
[ "$(DB_PATH="$tmp/v1.db" db_schema_version)" = '5' ]
[ "$(sqlite3 "$tmp/v1.db" "SELECT count(*) FROM pragma_table_info('accounts') WHERE name IN ('failed_attempts','last_failed_at','lock_until');")" = '3' ]
[ "$(sqlite3 "$tmp/v1.db" "SELECT count(*) FROM pragma_table_info('active_sessions') WHERE name='policy_period_start';")" = '1' ]

# A real v4 database must upgrade through migration 005 and preserve rows.
sqlite3 "$tmp/v4.db" <<'SQL'
CREATE TABLE schema_meta (version INTEGER PRIMARY KEY);
INSERT INTO schema_meta(version) VALUES (4);
CREATE TABLE auth_transactions (
    id INTEGER PRIMARY KEY,
    auth_key TEXT NOT NULL UNIQUE,
    account_id INTEGER NOT NULL,
    device_mac TEXT NOT NULL,
    profile_id INTEGER NOT NULL,
    policy_snapshot TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    consumed_at TEXT,
    state TEXT NOT NULL
);
INSERT INTO auth_transactions
    (id,auth_key,account_id,device_mac,profile_id,policy_snapshot,created_at,expires_at,state)
VALUES
    (7,'v4-auth-key',1,'AA:BB:CC:DD:EE:FF',1,'1|0|0|0|0|0|p|q',
     '2026-10-03T00:00:00Z','2026-10-03T00:15:00Z','pending');
SQL
DB_PATH="$tmp/v4.db" db_init
[ "$(DB_PATH="$tmp/v4.db" db_schema_version)" = '5' ]
[ "$(sqlite3 "$tmp/v4.db" "SELECT count(*) FROM pragma_table_info('auth_transactions') WHERE name IN ('rejection_reason','rejected_at');")" = '2' ]
[ "$(sqlite3 "$tmp/v4.db" "SELECT auth_key || ':' || state FROM auth_transactions WHERE id=7;")" = 'v4-auth-key:pending' ]
