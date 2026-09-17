-- Open-HotSpot schema v1.
-- Persistent state is local SQLite data; openNDS remains the enforcement engine.
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

CREATE TABLE IF NOT EXISTS schema_meta (
    version    INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS profiles (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT NOT NULL UNIQUE,
    period_type         TEXT NOT NULL DEFAULT 'none'
                        CHECK (period_type IN ('hourly','daily','monthly','yearly','none')),
    time_limit_s        INTEGER NOT NULL DEFAULT 0 CHECK (time_limit_s >= 0),
    upload_limit_b      INTEGER NOT NULL DEFAULT 0 CHECK (upload_limit_b >= 0),
    download_limit_b    INTEGER NOT NULL DEFAULT 0 CHECK (download_limit_b >= 0),
    upload_rate_kbps    INTEGER NOT NULL DEFAULT 0 CHECK (upload_rate_kbps >= 0),
    download_rate_kbps  INTEGER NOT NULL DEFAULT 0 CHECK (download_rate_kbps >= 0),
    max_devices         INTEGER NOT NULL DEFAULT 1 CHECK (max_devices >= 1),
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS accounts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT NOT NULL UNIQUE,
    pin_hash    TEXT NOT NULL,
    pin_salt    TEXT NOT NULL,
    pin_iter    INTEGER NOT NULL CHECK (pin_iter > 0),
    profile_id  INTEGER NOT NULL REFERENCES profiles(id),
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','suspended')),
    expires_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_accounts_status ON accounts(status, expires_at);

CREATE TABLE IF NOT EXISTS devices (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id  INTEGER NOT NULL REFERENCES accounts(id),
    mac         TEXT NOT NULL UNIQUE,
    hostname    TEXT,
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','blocked')),
    first_seen  TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen   TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_devices_account_status ON devices(account_id, status);

CREATE TABLE IF NOT EXISTS active_sessions (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id   INTEGER NOT NULL REFERENCES accounts(id),
    device_id    INTEGER NOT NULL REFERENCES devices(id),
    session_key  TEXT NOT NULL UNIQUE,
    started_at   TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    state        TEXT NOT NULL CHECK (state IN ('pending','active','closed')),
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    closed_at    TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_sessions_live
    ON active_sessions(session_key) WHERE state IN ('pending','active');
CREATE INDEX IF NOT EXISTS idx_active_sessions_account_live
    ON active_sessions(account_id, state);

CREATE TABLE IF NOT EXISTS usage_periods (
    account_id    INTEGER NOT NULL REFERENCES accounts(id),
    period_start  TEXT NOT NULL,
    period_end    TEXT NOT NULL,
    seconds_used  INTEGER NOT NULL DEFAULT 0 CHECK (seconds_used >= 0),
    bytes_up      INTEGER NOT NULL DEFAULT 0 CHECK (bytes_up >= 0),
    bytes_down    INTEGER NOT NULL DEFAULT 0 CHECK (bytes_down >= 0),
    closed        INTEGER NOT NULL DEFAULT 0 CHECK (closed IN (0,1)),
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    closed_at     TEXT,
    PRIMARY KEY (account_id, period_start)
);
CREATE INDEX IF NOT EXISTS idx_usage_periods_open
    ON usage_periods(account_id, closed, period_end);

CREATE TABLE IF NOT EXISTS usage_events (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    event_key        TEXT NOT NULL UNIQUE,
    account_id       INTEGER REFERENCES accounts(id),
    device_id        INTEGER REFERENCES devices(id),
    method           TEXT NOT NULL,
    mac              TEXT NOT NULL,
    bytes_incoming   INTEGER NOT NULL DEFAULT 0 CHECK (bytes_incoming >= 0),
    bytes_outgoing   INTEGER NOT NULL DEFAULT 0 CHECK (bytes_outgoing >= 0),
    session_start    TEXT NOT NULL,
    session_end      TEXT NOT NULL,
    received_at      TEXT NOT NULL DEFAULT (datetime('now')),
    detail           TEXT
);
CREATE INDEX IF NOT EXISTS idx_usage_events_account ON usage_events(account_id, received_at);

CREATE TABLE IF NOT EXISTS auth_transactions (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    auth_key          TEXT NOT NULL UNIQUE,
    account_id        INTEGER NOT NULL REFERENCES accounts(id),
    device_mac        TEXT NOT NULL,
    profile_id        INTEGER NOT NULL REFERENCES profiles(id),
    policy_snapshot   TEXT NOT NULL,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at        TEXT NOT NULL,
    consumed_at       TEXT,
    state             TEXT NOT NULL CHECK (state IN ('pending','consumed','rejected','expired'))
);
CREATE INDEX IF NOT EXISTS idx_auth_transactions_expiry ON auth_transactions(state, expires_at);

CREATE TABLE IF NOT EXISTS vouchers (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    code             TEXT NOT NULL UNIQUE,
    profile_id       INTEGER NOT NULL REFERENCES profiles(id),
    validity_seconds INTEGER NOT NULL CHECK (validity_seconds > 0),
    status           TEXT NOT NULL DEFAULT 'unused'
                     CHECK (status IN ('unused','redeemed','revoked')),
    redeemed_by      INTEGER REFERENCES accounts(id),
    redeemed_at      TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at       TEXT
);
CREATE INDEX IF NOT EXISTS idx_vouchers_status ON vouchers(status);

CREATE TABLE IF NOT EXISTS admin_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    ts         TEXT NOT NULL DEFAULT (datetime('now')),
    account_id INTEGER REFERENCES accounts(id),
    action     TEXT NOT NULL,
    detail     TEXT
);
CREATE INDEX IF NOT EXISTS idx_admin_events_ts ON admin_events(ts);

INSERT OR IGNORE INTO schema_meta(version) VALUES (1);
INSERT OR IGNORE INTO profiles
    (id, name, period_type, time_limit_s, upload_limit_b, download_limit_b,
     upload_rate_kbps, download_rate_kbps, max_devices)
VALUES (1, 'default-unlimited', 'none', 0, 0, 0, 0, 0, 1);
