# Data Model — Open-HotSpot v1.2

**Database**: SQLite 3, `/etc/open-hotspot/hotspot.db`  
**Journal mode**: WAL  
**Persistent application state**: SQLite only  
**Manager configuration**: UCI only

## 1. Storage Rules

At initialization the database must enable:

```sql
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;
```

The schema must be forward-migratable. No user/account/quota data is stored in
UCI.

All timestamps are persisted as UTC ISO-8601 text (`YYYY-MM-DDTHH:MM:SSZ`)
unless a column explicitly stores a date-only value.

## 2. `profiles`

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Profile ID |
| `name` | TEXT | UNIQUE NOT NULL | Human-readable name |
| `period_type` | TEXT | NOT NULL | hourly/daily/monthly/yearly/none |
| `time_limit_s` | INTEGER | NOT NULL >= 0 | Aggregate seconds per period |
| `upload_limit_b` | INTEGER | NOT NULL >= 0 | Aggregate upload bytes |
| `download_limit_b` | INTEGER | NOT NULL >= 0 | Aggregate download bytes |
| `upload_rate_kbps` | INTEGER | NOT NULL >= 0 | Native openNDS upload rate |
| `download_rate_kbps` | INTEGER | NOT NULL >= 0 | Native openNDS download rate |
| `max_devices` | INTEGER | NOT NULL >= 1 | Maximum simultaneous devices |
| `created_at` | TEXT | NOT NULL | Creation time |
| `updated_at` | TEXT | NOT NULL | Last update |

`0` means unlimited for time/data/rate dimensions. `max_devices` cannot be zero.

## 3. `accounts`

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Account identity |
| `username` | TEXT | UNIQUE NOT NULL | Login name |
| `pin_hash` | TEXT | NOT NULL | KDF output/encoded verifier |
| `pin_salt` | TEXT | NOT NULL | Unique random salt |
| `pin_iter` | INTEGER | NOT NULL | KDF cost used for this account |
| `profile_id` | INTEGER | FK NOT NULL | Assigned policy profile |
| `status` | TEXT | NOT NULL | active/suspended |
| `expires_at` | TEXT | nullable | Hard expiry in UTC |
| `failed_attempts` | INTEGER | NOT NULL >= 0 | Consecutive failed PIN attempts |
| `last_failed_at` | TEXT | nullable | Last failed PIN timestamp |
| `lock_until` | TEXT | nullable | Temporary login backoff end in UTC |
| `created_at` | TEXT | NOT NULL | Creation time |
| `updated_at` | TEXT | NOT NULL | Last update |
| `deleted_at` | TEXT | nullable | Soft-delete marker, if retained |

Username normalization is defined by the implementation and must be consistent
for create, lookup, and authentication.

## 4. `devices`

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Device ID |
| `account_id` | INTEGER | FK NOT NULL | Owning account |
| `mac` | TEXT | UNIQUE NOT NULL | Normalized MAC |
| `hostname` | TEXT | nullable | Best-effort client name |
| `status` | TEXT | NOT NULL | active/blocked |
| `first_seen` | TEXT | NOT NULL | First registration |
| `last_seen` | TEXT | nullable | Last observed event |
| `created_at` | TEXT | NOT NULL | Row creation |
| `updated_at` | TEXT | NOT NULL | Last update |

A MAC is globally unique in the local database. Reassignment between accounts
requires an explicit administrative operation; an authentication attempt may
not silently move a device to another account.

## 5. `active_sessions`

This table represents manager-known live authorization state. It is not the
source of truth for historical usage; it is a concurrency/control aid.

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Local session record |
| `account_id` | INTEGER | FK NOT NULL | Account |
| `device_id` | INTEGER | FK NOT NULL | Device |
| `session_key` | TEXT | UNIQUE NOT NULL | Verified openNDS/session identity when available |
| `started_at` | TEXT | NOT NULL | Session start |
| `last_seen_at` | TEXT | NOT NULL | Last manager event |
| `state` | TEXT | NOT NULL | pending/active/closed |
| `policy_period_start` | TEXT | nullable | Period for which native policy was last refreshed |
| `created_at` | TEXT | NOT NULL | Row creation |
| `closed_at` | TEXT | nullable | Close time |

If the resolved openNDS build does not expose a stable session identifier, the
implementation must define a collision-resistant composite key in Phase 0;
it must not silently assume one exists.

A partial unique index must prevent more than one `active` row for the same
openNDS session identity. A query/transaction over `active_sessions` is used to
enforce `profiles.max_devices` atomically.

Schema version 3 adds `policy_period_start`. The cycle job uses it to refresh
native openNDS policy once per period; a failed refresh leaves the marker
unchanged for a bounded retry.

## 6. `usage_periods`

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `account_id` | INTEGER | FK | Account |
| `period_start` | TEXT | PK part | UTC start |
| `period_end` | TEXT | NOT NULL | UTC end |
| `seconds_used` | INTEGER | NOT NULL >= 0 | Aggregate seconds |
| `bytes_up` | INTEGER | NOT NULL >= 0 | Aggregate upload |
| `bytes_down` | INTEGER | NOT NULL >= 0 | Aggregate download |
| `closed` | INTEGER | NOT NULL | 0=open, 1=closed |
| `created_at` | TEXT | NOT NULL | Creation |
| `closed_at` | TEXT | nullable | Archive time |

Primary key: `(account_id, period_start)`.

The current period is the unique open period for an account. Historical periods
remain immutable except for controlled migration/reconciliation operations.

## 7. `usage_events`

This is the raw accounting/idempotency layer.

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Event row |
| `event_key` | TEXT | UNIQUE NOT NULL | Stable deduplication key |
| `account_id` | INTEGER | FK nullable | Resolved account |
| `device_id` | INTEGER | FK nullable | Resolved device |
| `method` | TEXT | NOT NULL | BinAuth event method |
| `mac` | TEXT | NOT NULL | MAC from openNDS |
| `bytes_incoming` | INTEGER | NOT NULL >= 0 | Raw openNDS counter |
| `bytes_outgoing` | INTEGER | NOT NULL >= 0 | Raw openNDS counter |
| `session_start` | TEXT | NOT NULL | Raw start value |
| `session_end` | TEXT | NOT NULL | Raw end value |
| `received_at` | TEXT | NOT NULL | Manager receive time |
| `detail` | TEXT | nullable | Bounded diagnostic detail |

`event_key` is generated from the verified event/session identity defined by
Phase 0. It must not include a variable such as `method` merely to make keys
unique if the same underlying session can produce multiple callbacks.

## 8. `auth_transactions`

This table bridges local FAS verification and the later openNDS authorization
event without making the MAC the account identity.

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Transaction ID |
| `auth_key` | TEXT | UNIQUE NOT NULL | Opaque one-time handoff key |
| `account_id` | INTEGER | FK NOT NULL | Verified account |
| `device_mac` | TEXT | NOT NULL | MAC observed by FAS/openNDS |
| `profile_id` | INTEGER | FK NOT NULL | Policy snapshot source |
| `policy_snapshot` | TEXT | NOT NULL | Minimal serialized policy context |
| `created_at` | TEXT | NOT NULL | Creation |
| `expires_at` | TEXT | NOT NULL | Short-lived expiry |
| `consumed_at` | TEXT | nullable | BinAuth/auth consumption |
| `state` | TEXT | NOT NULL | pending/consumed/rejected/expired |

The exact handoff field/encoding is a Phase 0 gate. The table is deliberately
opaque to the portal: it prevents the portal from inventing or changing an
account identity after PIN verification.

## 9. `vouchers`

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Voucher ID |
| `code` | TEXT | UNIQUE NOT NULL | Random voucher code |
| `profile_id` | INTEGER | FK NOT NULL | Profile applied on redemption |
| `validity_seconds` | INTEGER | NOT NULL > 0 | Account hard-expiry interval |
| `status` | TEXT | NOT NULL | unused/redeemed/revoked |
| `redeemed_by` | INTEGER | FK nullable | Resulting account |
| `redeemed_at` | TEXT | nullable | Redemption time |
| `created_at` | TEXT | NOT NULL | Creation |
| `expires_at` | TEXT | nullable | Voucher expiry, if used |

## 10. `admin_events`

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| `id` | INTEGER | PK | Event ID |
| `ts` | TEXT | NOT NULL | UTC timestamp |
| `account_id` | INTEGER | FK nullable | Related account |
| `action` | TEXT | NOT NULL | Admin/system action |
| `detail` | TEXT | nullable | Bounded non-secret detail |

PINs, salts, raw authentication handoff keys, and other secrets must never be
written here.

## 11. `schema_meta`

| Column | Type | Meaning |
|---|---|---|
| `version` | INTEGER | Schema version |
| `applied_at` | TEXT | Migration timestamp |

Migrations are monotonic and idempotent. Version 2 adds bounded PIN-failure
backoff fields to `accounts`.

## 12. Transaction Patterns

### Accounting

```sql
BEGIN IMMEDIATE;
  INSERT INTO usage_events (...)
  VALUES (...)
  ON CONFLICT(event_key) DO NOTHING;

  -- only if the insert changed one row:
  --   resolve the affected period(s)
  --   update usage_periods
  --   update active_sessions/device timestamps
COMMIT;
```

No aggregate update may happen when the event was already present.

### Voucher redemption

```sql
BEGIN IMMEDIATE;
  UPDATE vouchers
     SET status='redeemed', redeemed_by=?, redeemed_at=?
   WHERE code=? AND status='unused';
  -- require changes() = 1
  -- create account using the voucher's bound profile
COMMIT;
```

### Simultaneous-device authorization

The verified authorization path must perform a transaction equivalent to:

```text
BEGIN IMMEDIATE
  validate account status/expiry
  validate device status/ownership
  count active_sessions for account
  reject if count >= max_devices and this device is not already active
  create/consume auth transaction
COMMIT
```

The implementation must use the actual openNDS event/session identity confirmed
by Phase 0; no UI count is authoritative.

## 13. UCI Configuration

`/etc/config/open-hotspot` contains manager settings only:

```text
config manager 'global'
    option check_interval '300'
    option default_profile '1'
    option active_template 'default'
    option history_retention '90'
    option log_retention_kb '256'
    option pin_kdf 'pbkdf2-sha256'
    option pin_iterations 'REPLACE_AFTER_BENCHMARK'
```

`check_interval` has a hard floor of 60 seconds.

## 14. Referential Integrity and Deletion

- Deleting a profile referenced by an account is rejected until reassigned.
- Deleting an account is soft-delete first if historical audit data references it.
- Deleting a device is administrative removal; its historical usage remains.
- Usage and accounting rows are never deleted merely because a device is removed.

## 15. Units Contract

| Concept | SQLite storage | openNDS boundary |
|---|---|---|
| Time budget | seconds | target contract verified in Phase 0 |
| Traffic counters | bytes | raw openNDS counters preserved |
| Volume quota | bytes | target openNDS unit verified in Phase 0 |
| Rate | integer kbps field | target openNDS unit verified in Phase 0 |

The database model does not guess openNDS units.
