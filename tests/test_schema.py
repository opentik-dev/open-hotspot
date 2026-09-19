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
        self.assertEqual(self.db.execute("SELECT max(version) FROM schema_meta").fetchone()[0], 4)
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


if __name__ == "__main__":
    unittest.main()
