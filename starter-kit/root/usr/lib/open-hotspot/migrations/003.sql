BEGIN IMMEDIATE;
ALTER TABLE active_sessions ADD COLUMN policy_period_start TEXT;
INSERT OR IGNORE INTO schema_meta(version) VALUES (3);
COMMIT;
