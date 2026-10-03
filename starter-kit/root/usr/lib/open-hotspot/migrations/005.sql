BEGIN IMMEDIATE;
ALTER TABLE auth_transactions ADD COLUMN rejection_reason TEXT;
ALTER TABLE auth_transactions ADD COLUMN rejected_at TEXT;
INSERT OR IGNORE INTO schema_meta(version) VALUES (5);
COMMIT;
