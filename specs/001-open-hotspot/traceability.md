# Constitution traceability — 2026-09-18

This review maps the current implementation to `.specify/memory/constitution.md`.
It is an evidence review, not a release approval; the target-only gates listed
at the end remain blocking.

| Principle | Evidence in implementation | Result |
| --- | --- | --- |
| I. openNDS remains enforcement engine | `opennds.sh` is the only control adapter; quotas/rates are sent through verified `ndsctl auth`; no custom packet counter or nftables quota path exists. | Pass, runtime quota cutoff still pending |
| II. Target behavior is evidenced | `research.md` records target OpenWrt/openNDS version, FAS, BinAuth, and native units; `binauth.sh` has method-specific parsers. | Pass for resolved contracts; counter/restart gates open |
| III. New identity decisions fail closed | FAS requires valid context and credentials; `db_auth_consume` requires a live transaction and active account; BinAuth rejects malformed/unknown callbacks. Existing sessions are not deauthed by BinAuth failure. | Pass |
| IV. SQLite is transactional/idempotent | WAL, foreign keys, unique event keys, `BEGIN IMMEDIATE`, voucher conditional redemption, and per-connection SQLite timeout. Target race proof admitted 2/3 devices and redeemed one voucher once. | Pass |
| V. Security/privacy are defaults | PBKDF2-HMAC-SHA256, PIN backoff, allow-list validation, PDO prepared statements, no PIN logging/export, and no `ndsctl` in BinAuth. | Pass by code/tests |
| VI. Small/auditable OpenWrt integration | POSIX shell, LuCI CBI/RPC, bounded cron jobs, `flock`, no permanent manager loop, optional `dnsmasq-full`, focused APK build. | Pass |

## Blocking evidence still required

The following are intentionally not marked complete in `tasks.md`:

- T006: a real traffic experiment must map openNDS incoming/outgoing counters
  to upload/download fields.
- T011: reboot and openNDS restart must be tested separately for restore and
  persistent usage behavior.
- T012: a disposable client must complete portal → FAS → openNDS authorization
  → BinAuth → native enforcement → close/accounting.
- T086–T088: connected-client failure behavior, interrupted setup recovery, and
  the complete physical-router walkthrough still need execution.
- FR-050: force-deauth is now available through the verified adapter, RPC, and
  LuCI device view; real-client accounting after administrative deauth still
  belongs to T012/T088.
- US-5/quickstart renewal: implemented through `account_renew`. It records
  `accounts.renewed_at`, preserves prior aggregates, deauthenticates active
  devices through the verified adapter, and starts the effective quota window
  at that UTC instant. Physical reconnect and accounting proof remains part of
  T012/T088.
- FR-017/MAC reassignment: implemented through the explicit audited
  `device_reassign` RPC/LuCI action. It requires an active target account and
  no live session; authentication cannot perform reassignment implicitly.
- FR-072/T066: backup export/import is exposed through the authenticated LuCI
  page using fixed temporary paths; the helper validates the archive before
  import and creates a rollback archive.
- T090: the v1.2 baseline must not be frozen while the blocking gates above are
  open.
