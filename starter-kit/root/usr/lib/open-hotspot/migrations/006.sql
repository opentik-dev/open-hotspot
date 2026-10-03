PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;

CREATE TABLE IF NOT EXISTS admin_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    ts         TEXT NOT NULL DEFAULT (datetime('now')),
    account_id INTEGER REFERENCES accounts(id),
    action     TEXT NOT NULL,
    detail     TEXT
);

DROP TABLE IF EXISTS _defaults_v6;
CREATE TABLE _defaults_v6 (
    category TEXT NOT NULL,
    severity TEXT NOT NULL,
    source   TEXT NOT NULL,
    result   TEXT NOT NULL
);
INSERT INTO _defaults_v6 VALUES ('system', 'info', 'system', 'success');

DROP TABLE IF EXISTS _admin_events_v6;
CREATE TABLE _admin_events_v6 (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    ts         TEXT NOT NULL DEFAULT (datetime('now')),
    account_id INTEGER REFERENCES accounts(id),
    action     TEXT NOT NULL,
    detail     TEXT,
    category   TEXT NOT NULL DEFAULT 'system'
               CHECK (category IN ('devices','accounts','sessions','quota','system','security','backup')),
    severity   TEXT NOT NULL DEFAULT 'info'
               CHECK (severity IN ('info','success','warning','error')),
    source     TEXT NOT NULL DEFAULT 'system'
               CHECK (source IN ('luci','rpc','fas','binauth','cycle','restore','system')),
    result     TEXT NOT NULL DEFAULT 'success'
               CHECK (result IN ('success','denied','failed','reconciled'))
);

INSERT INTO _admin_events_v6 (id, ts, account_id, action, detail, category, severity, source, result)
SELECT * FROM admin_events NATURAL LEFT JOIN _defaults_v6;

DROP TABLE admin_events;
ALTER TABLE _admin_events_v6 RENAME TO admin_events;
DROP TABLE IF EXISTS _defaults_v6;

CREATE INDEX IF NOT EXISTS idx_admin_events_ts ON admin_events(ts);
CREATE INDEX IF NOT EXISTS idx_admin_events_filter ON admin_events(category, severity, source, result);
INSERT OR IGNORE INTO schema_meta(version) VALUES (6);

COMMIT;
PRAGMA foreign_keys = ON;
