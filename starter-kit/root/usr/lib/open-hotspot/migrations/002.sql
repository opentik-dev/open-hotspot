BEGIN IMMEDIATE;
ALTER TABLE accounts ADD COLUMN failed_attempts INTEGER NOT NULL DEFAULT 0
    CHECK (failed_attempts >= 0);
ALTER TABLE accounts ADD COLUMN last_failed_at TEXT;
ALTER TABLE accounts ADD COLUMN lock_until TEXT;
INSERT OR IGNORE INTO schema_meta(version) VALUES (2);
COMMIT;
