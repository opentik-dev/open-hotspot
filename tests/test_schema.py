"""Host-side contract tests for the SQLite domain schema.

The production target uses sqlite3-cli. Python's standard-library SQLite
driver keeps these tests runnable in a clean development environment without
adding a project dependency.
"""

from pathlib import Path
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "starter-kit/root/usr/lib/open-hotspot/schema.sql"


class SchemaContractTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.executescript(SCHEMA.read_text(encoding="utf-8"))

    def tearDown(self):
        self.db.close()

    def test_schema_is_idempotent_and_has_required_tables(self):
        self.db.executescript(SCHEMA.read_text(encoding="utf-8"))
        names = {
            row[0]
            for row in self.db.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        self.assertTrue(
            {
                "schema_meta",
                "profiles",
                "accounts",
                "devices",
                "active_sessions",
                "usage_periods",
                "usage_events",
                "auth_transactions",
                "vouchers",
                "admin_events",
            }.issubset(names)
        )
        self.assertEqual(self.db.execute("SELECT max(version) FROM schema_meta").fetchone()[0], 6)
        self.assertEqual(
            self.db.execute("SELECT name FROM profiles WHERE id=1").fetchone()[0],
            "default-unlimited",
        )

    def test_domain_constraints_reject_invalid_profile_and_status(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO profiles(name, max_devices) VALUES ('bad', 0)"
            )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO profiles(name, period_type) VALUES ('bad2', 'weekly')"
            )

    def test_voucher_transition_is_one_time(self):
        self.db.execute("INSERT INTO profiles(name) VALUES ('daily')")
        profile_id = self.db.execute(
            "SELECT id FROM profiles WHERE name='daily'"
        ).fetchone()[0]
        self.db.execute(
            "INSERT INTO accounts(username,pin_hash,pin_salt,pin_iter,profile_id) "
            "VALUES ('a','h','s',1000,?)",
            (profile_id,),
        )
        account_id = self.db.execute(
            "SELECT id FROM accounts WHERE username='a'"
        ).fetchone()[0]
        self.db.execute(
            "INSERT INTO vouchers(code,profile_id,validity_seconds) VALUES ('ABC123',?,3600)",
            (profile_id,),
        )
        self.db.commit()
        self.db.execute("BEGIN IMMEDIATE")
        first = self.db.execute(
            "UPDATE vouchers SET status='redeemed', redeemed_by=? "
            "WHERE code='ABC123' AND status='unused'",
            (account_id,),
        ).rowcount
        self.db.commit()
        self.assertEqual(first, 1)
        self.db.execute("BEGIN IMMEDIATE")
        second = self.db.execute(
            "UPDATE vouchers SET status='redeemed', redeemed_by=? "
            "WHERE code='ABC123' AND status='unused'",
            (account_id,),
        ).rowcount
        self.db.commit()
        self.assertEqual(second, 0)

    def test_usage_event_key_prevents_double_accrual(self):
        self.db.execute("INSERT INTO profiles(name) VALUES ('daily')")
        profile_id = self.db.execute(
            "SELECT id FROM profiles WHERE name='daily'"
        ).fetchone()[0]
        self.db.execute(
            "INSERT INTO accounts(username,pin_hash,pin_salt,pin_iter,profile_id) "
            "VALUES ('a','h','s',1000,?)",
            (profile_id,),
        )
        account_id = self.db.execute("SELECT id FROM accounts").fetchone()[0]
        self.db.execute(
            "INSERT INTO devices(account_id,mac) VALUES (?, 'AA:BB:CC:DD:EE:FF')",
            (account_id,),
        )
        device_id = self.db.execute("SELECT id FROM devices").fetchone()[0]

        for _ in range(2):
            self.db.execute("BEGIN IMMEDIATE")
            self.db.execute(
                "INSERT OR IGNORE INTO usage_events "
                "(event_key,account_id,device_id,method,mac,bytes_incoming,bytes_outgoing,session_start,session_end) "
                "VALUES ('1:100:160',?,?,?,?,?,?,?,?)",
                (account_id, device_id, "client_deauth", "AA:BB:CC:DD:EE:FF", 20, 10, "100", "160"),
            )
            if self.db.execute("SELECT changes()").fetchone()[0] == 1:
                self.db.execute(
                    "INSERT INTO usage_periods(account_id,period_start,period_end,seconds_used,bytes_up,bytes_down) "
                    "VALUES (?,?,?,?,?,?) ON CONFLICT(account_id,period_start) DO UPDATE SET "
                    "seconds_used=seconds_used+excluded.seconds_used, "
                    "bytes_up=bytes_up+excluded.bytes_up, bytes_down=bytes_down+excluded.bytes_down",
                    (account_id, "p", "q", 60, 10, 20),
                )
            self.db.commit()

        self.assertEqual(
            self.db.execute(
                "SELECT seconds_used,bytes_up,bytes_down FROM usage_periods"
            ).fetchone(),
            (60, 10, 20),
        )

    def test_renewal_state_and_audited_reassignment_fields_exist(self):
        account_columns = {
            row[1] for row in self.db.execute("PRAGMA table_info(accounts)")
        }
        self.assertIn("renewed_at", account_columns)
        auth_columns = {
            row[1] for row in self.db.execute("PRAGMA table_info(auth_transactions)")
        }
        self.assertIn("rejection_reason", auth_columns)
        self.assertIn("rejected_at", auth_columns)
        self.db.execute(
            "INSERT INTO accounts(username,pin_hash,pin_salt,pin_iter,profile_id) "
            "VALUES ('renewed','h','s',1000,1)"
        )
        account_id = self.db.execute(
            "SELECT id FROM accounts WHERE username='renewed'"
        ).fetchone()[0]
        self.db.execute(
            "UPDATE accounts SET renewed_at='2026-09-18T12:00:00Z' WHERE id=?",
            (account_id,),
        )
        self.assertEqual(
            self.db.execute(
                "SELECT renewed_at FROM accounts WHERE id=?", (account_id,)
            ).fetchone()[0],
            "2026-09-18T12:00:00Z",
        )

    def test_admin_events_has_taxonomy_columns_and_constraints(self):
        event_columns = {
            row[1] for row in self.db.execute("PRAGMA table_info(admin_events)")
        }
        self.assertIn("category", event_columns)
        self.assertIn("severity", event_columns)
        self.assertIn("source", event_columns)
        self.assertIn("result", event_columns)

        # Default values
        self.db.execute("INSERT INTO admin_events(action) VALUES ('test_action')")
        row = self.db.execute(
            "SELECT category, severity, source, result FROM admin_events WHERE action='test_action'"
        ).fetchone()
        self.assertEqual(row, ("system", "info", "system", "success"))

        # Valid custom values
        self.db.execute(
            "INSERT INTO admin_events(action, category, severity, source, result) "
            "VALUES ('valid_event', 'devices', 'warning', 'rpc', 'denied')"
        )
        row = self.db.execute(
            "SELECT category, severity, source, result FROM admin_events WHERE action='valid_event'"
        ).fetchone()
        self.assertEqual(row, ("devices", "warning", "rpc", "denied"))

        # Invalid category CHECK constraint
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO admin_events(action, category) VALUES ('bad', 'invalid_cat')")

        # Invalid severity CHECK constraint
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO admin_events(action, severity) VALUES ('bad', 'critical')")

        # Invalid source CHECK constraint
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO admin_events(action, source) VALUES ('bad', 'external')")

        # Invalid result CHECK constraint
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO admin_events(action, result) VALUES ('bad', 'unknown')")

    def test_migration_006_preserves_existing_events_and_is_idempotent(self):
        migration_006 = ROOT / "starter-kit/root/usr/lib/open-hotspot/migrations/006.sql"
        db = sqlite3.connect(":memory:", isolation_level=None)
        db.execute("PRAGMA foreign_keys = ON")
        db.executescript(
            """
            CREATE TABLE schema_meta (
                version    INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            INSERT INTO schema_meta(version) VALUES (1), (2), (3), (4), (5);
            CREATE TABLE accounts (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                username        TEXT NOT NULL UNIQUE,
                pin_hash        TEXT NOT NULL,
                pin_salt        TEXT NOT NULL,
                pin_iter        INTEGER NOT NULL,
                profile_id      INTEGER NOT NULL,
                status          TEXT NOT NULL DEFAULT 'active',
                expires_at      TEXT,
                deleted_at      TEXT,
                failed_attempts INTEGER NOT NULL DEFAULT 0,
                last_failed_at  TEXT,
                lock_until      TEXT,
                renewed_at      TEXT
            );
            INSERT INTO accounts(id, username, pin_hash, pin_salt, pin_iter, profile_id)
            VALUES (99, 'user99', 'h', 's', 1000, 1), (10, 'user10', 'h', 's', 1000, 1);
            CREATE TABLE admin_events (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                ts         TEXT NOT NULL DEFAULT (datetime('now')),
                account_id INTEGER REFERENCES accounts(id),
                action     TEXT NOT NULL,
                detail     TEXT
            );
            INSERT INTO admin_events(id, ts, account_id, action, detail)
            VALUES (42, '2026-10-01 12:34:56', 99, 'legacy_action', 'legacy detail string');
            """
        )
        # Apply migration 006
        db.executescript(migration_006.read_text(encoding="utf-8"))
        self.assertEqual(db.execute("SELECT max(version) FROM schema_meta").fetchone()[0], 6)

        # Existing legacy event is completely preserved and assigned default taxonomy
        row = db.execute(
            "SELECT id, ts, account_id, action, detail, category, severity, source, result "
            "FROM admin_events WHERE id=42"
        ).fetchone()
        self.assertEqual(
            row,
            (42, '2026-10-01 12:34:56', 99, 'legacy_action', 'legacy detail string', 'system', 'info', 'system', 'success'),
        )

        # Insert a custom v6 event with devices / error / rpc / failed
        db.execute(
            "INSERT INTO admin_events(id, ts, account_id, action, detail, category, severity, source, result) "
            "VALUES (100, '2026-10-03 14:00:00', 10, 'rpc_error_action', 'rpc failed detail', 'devices', 'error', 'rpc', 'failed')"
        )

        # Re-running migration 006 on this v6 DB is idempotent, preserves existing taxonomy, and does not fail
        db.executescript(migration_006.read_text(encoding="utf-8"))
        self.assertEqual(db.execute("SELECT max(version) FROM schema_meta").fetchone()[0], 6)

        # Assert custom taxonomy and all fields remain intact
        custom_row = db.execute(
            "SELECT id, ts, account_id, action, detail, category, severity, source, result "
            "FROM admin_events WHERE id=100"
        ).fetchone()
        self.assertEqual(
            custom_row,
            (100, '2026-10-03 14:00:00', 10, 'rpc_error_action', 'rpc failed detail', 'devices', 'error', 'rpc', 'failed'),
        )

        # Assert legacy row remains unchanged
        row_again = db.execute(
            "SELECT id, ts, account_id, action, detail, category, severity, source, result "
            "FROM admin_events WHERE id=42"
        ).fetchone()
        self.assertEqual(row, row_again)

        # Verify foreign keys are intact
        self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

        # Re-running schema.sql on this DB is idempotent
        db.executescript(SCHEMA.read_text(encoding="utf-8"))
        self.assertEqual(db.execute("SELECT max(version) FROM schema_meta").fetchone()[0], 6)

        # Applying migration 006 on a DB initialized directly from schema.sql v6 causes no duplicate column conflict
        fresh_db = sqlite3.connect(":memory:", isolation_level=None)
        fresh_db.execute("PRAGMA foreign_keys = ON")
        fresh_db.executescript(SCHEMA.read_text(encoding="utf-8"))
        fresh_db.executescript(migration_006.read_text(encoding="utf-8"))
        self.assertEqual(fresh_db.execute("SELECT max(version) FROM schema_meta").fetchone()[0], 6)
        fresh_db.close()
        db.close()


if __name__ == "__main__":
    unittest.main()
