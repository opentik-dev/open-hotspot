# Changelog

This file summarizes user-visible and engineering-significant changes. The
release ledger and field checkpoints remain in [`docs/release-history.md`](docs/release-history.md).

## Unreleased

## 1.2.0-r92 (unpublished working-tree candidate)

- Stabilized authenticated session lifecycle (Candidate implementation; Tested locally, Pending Hardware Validation on physical router):
  - Replaced indiscriminate client iteration in `session-restore.sh reconcile_stale` with `opennds_authenticated_macs` parser, preventing Preauthenticated discovery probes from triggering invalid deauthentications or aborting the reconciliation cycle.
  - Added `COLLATE NOCASE` to MAC address comparisons in `db.sh` (`db_device_get_by_mac`, `db_active_session_count_by_mac`, `db_session_key_by_mac`, `db_session_period_type`, and `db_session_close`), eliminating session drops caused by casing mismatches between openNDS (lowercase) and SQLite (uppercase).
  - Populated `policy_period_start` in `active_sessions` upon session consumption in `db_auth_consume`, preventing redundant and disruptive `opennds_apply_session_policy` invocations on every cron cycle tick.
  - Added retry guard in `ensure_opennds_runtime` before restarting the openNDS service if the daemon process is actively running, preventing transient socket checks from resetting live client connections.
  - Captured return code of `opennds_deauth` in `session-restore.sh`, logging `native_restore_reconciled` on success and `native_restore_reconcile_failed` with `reconcile:deauth_rc=$deauth_rc` on failure without leaking MAC/IP/PIN/tokens.
- Reproducible APK packaging:
  - Updated `tools/build-apk.sh` with deterministic `SOURCE_DATE_EPOCH`, normalized file permissions, and clamped mtimes.
  - Added `--verify` flag to run independent builds and verify bit-for-bit identical checksums.
  - Added regression test `tests/test_apk_reproducibility.sh`.
- Hardened DEV diagnostics:
  - Added pure-shell watchdog timer in `rpc_dev_diagnose` for platforms where external `timeout` binary is unavailable.
  - Added on-target package version discovery via `/usr/lib/open-hotspot/open-hotspot.version` and packaging metadata.
- Reconciled release metadata: r90 remains the last field-tested acceptance candidate; r92 is explicitly marked as unpublished working-tree state in all active documentation.
- Added comprehensive test coverage: extended regression test `tests/test_session_stability.sh`, release consistency contract `tests/test_release_consistency.sh`, and APK reproducibility test `tests/test_apk_reproducibility.sh` (5 python tests, 27 shell contracts passed).
- Read-only DEV diagnostics LuCI page (Services → Open-HotSpot → DEV) and RPC methods (`dev_events_list`, `dev_diagnose`).
- Improved diagnostic detail in `cycle.sh` events with safe exit code capture and non-secret context.
- No changes to authentication fail-closed semantics or openNDS contracts. All hardware gates remain open.

## 1.2.0-r91 (superseded)

- Pre-release iteration: added DEV diagnostics page and consistency test, but lacked session stability fixes and commit was not self-contained. Superseded by r92.

### Previous governance changes (included in r91 working tree)

- Added a shared agent working agreement and a project-status model that
  distinguishes implemented, tested, verified, and accepted behavior.
- Separated public product documentation from Spec-Kit and target-debugging
  details.
- Added the proposed openNDS 11 compatibility decision and adapter contract.
- Kept openNDS 10.3.1-r3 and Open-HotSpot 1.2.0-r60 as the rollback baseline
  while v11 remains an isolated migration track.

## 1.2.0-r60

- Added configurable manager-owned session restoration behavior.
- Added target-specific live-client resolution without hardcoded router
  addresses.
- Preserved fail-closed authentication, SQLite accounting, and the documented
  router-access isolation controls.
- See the [release gates](docs/release-gates.md) before treating this candidate
  as production-ready.

## Historical checkpoints

Detailed r16–r60 package checkpoints and target evidence are preserved in
[`docs/release-history.md`](docs/release-history.md) and
[`docs/field-evidence-20260918.md`](docs/field-evidence-20260918.md).
