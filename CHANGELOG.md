# Changelog

This file summarizes user-visible and engineering-significant changes. The
release ledger and field checkpoints remain in [`docs/release-history.md`](docs/release-history.md).

## 1.2.0-r100 (candidate; hardware acceptance pending)

- Devices UI clarity:
  - Separates the device label from the current account owner, using the stored
    hostname when available and a stable `Device #<id>` fallback otherwise.
  - Groups device actions in responsive cards so Block, Remove/Disconnect, and
    Reassign remain visible and aligned on desktop and narrow screens.

- Controlled account switching hardening:
  - Added schema migration 005 with persisted `rejection_reason` and
    `rejected_at` fields for deterministic callback retries.
  - Added transactional device admission that permits a switch only when the
    previous account is inactive/expired/deleted/exhausted and the device has
    no live or pending session.
  - Added full policy/remaining-quota revalidation, `changes() == 1` guards,
    rollback-safe session creation, redacted `device_account_switched` and
    `device_switch_denied` events, and a 21-scenario contract suite.
  - Reassign now returns explicit machine-readable reasons instead of generic
    validation failures.

- Device removal lifecycle and failure observability hardening:
  - Added machine-readable failure reasons to `admin.sh device-remove`: `invalid-id`,
    `device-not-found`, `live-session`, `usage-history`, and `database`.
  - Added safe administrative audit logging: logs `device_removed` with numeric
    entity identifiers on successful deletion, and `device_remove_denied` with safe
    reasons on rejection without exposing raw MAC addresses, IPs, PINs, or tokens.
  - Updated rpcd `open_hotspot` to route `device_remove` through `rpc_device_remove`,
    propagating the real failure reason over ubus rather than collapsing to generic
    `validation` error.
  - Added explicit `has_history` boolean and `lifecycle_state` (`live`, `historical`,
    `removable`) to `device_list` with strict `live > historical > removable` precedence.
  - Updated LuCI Devices view and controller to provide actionable human-readable
    guidance: disabling removal on historical devices with clear reason (“Historical device
    retained for accounting; use Reassign. Archive is planned separately.”), directing active
    sessions to Disconnect first, and displaying compact status badges and hints.
  - Added automated controlled database-failure test (SQLite trigger `RAISE(FAIL)`) and
    concurrency/race condition test, proving foreign-key and transactional integrity
    guarantee that a device cannot be deleted if a session or usage reference appears.
  - Maintained strict historical accounting protection and foreign-key integrity;
    devices referenced by active sessions or usage events are never physically deleted.

- Prepared r97 account-status clarity: unlimited time/data limits now render
  as `Unlimited` instead of the internal zero sentinel. Added the DNS Insights
  decision record and kept its DEV registry entry design-only and disabled.

- Prepared r96 visual card redesign: compacted the account/profile creation
  forms and placed each editable record and its actions inside a responsive,
  consistently bordered card.

- Prepared r95 UI/units hardening: compact responsive create forms, consistent
  action rows, and direct unit selectors for time, data limits, and rates.
  Multi-day first-login validity presets are intentionally not enabled yet;
  they require a separate rolling-validity database and accounting contract.

- Prepared r94 UI hardening: Events and DEV now load the shared stylesheet, and
  account/device action controls use consistent responsive rows and button
  sizing.

- Separated the LuCI developer surfaces:
  - `Services → Open-HotSpot → Events` now owns the bounded, read-only and
    redacted manager event log plus the diagnostic snapshot.
  - `Services → Open-HotSpot → DEV` is now a future-feature registry and does
    not expose event data, diagnostics, UCI writes, firewall changes, or
    client-bypass controls.
- Documented the IoT bypass idea for a later reviewed contract; Tapo/D-Link
  devices remain disabled until admission, expiry, audit, and rollback rules
  are implemented and tested.

## 1.2.0-r98 (device-lifecycle candidate; acceptance pending)

- Added machine-readable device-removal outcomes, lifecycle indicators, pending-session alignment, safe failure events, and transactional race/failure regression coverage.
- This candidate has not been installed on the router; r97 remains the last installed field artifact.

## 1.2.0-r97 (UI/account-status candidate; acceptance pending)

- Clarified unlimited account status display without changing quota arithmetic,
  openNDS policy conversion, or accounting.
- Added `docs/dns-observability-plan.md`; no DNS collector or resolver mutation
  is included or enabled.

## 1.2.0-r96 (superseded installed UI candidate; acceptance pending)

- Replaced the loose account/profile record layout with bordered responsive
  cards containing the editable fields and their action controls.
- Compressed the account/profile creation forms into aligned two-column grids;
  retained the existing unit conversion and runtime/session behavior.
- Updated the deployment contract and simulations to derive the current APK
  release instead of remaining pinned to an older artifact.

## 1.2.0-r95 (superseded installed field candidate; acceptance pending)

- Added seconds/minutes/hours/days selectors for time limits, B/KiB/MiB/GiB
  selectors for data limits, and kbit/s/Mbit/s/Gbit/s selectors for rates.
- Tightened account/profile creation layouts and action-button alignment for
  long lists and narrow screens.
- Kept the existing r94 runtime and session behavior unchanged.
- Installed over r94 on the EA8300; post-install preflight, diagnostics, and
  `ndsctl status` passed. Multi-day first-login validity presets remain
  intentionally deferred pending a rolling-validity accounting contract.

## 1.2.0-r94 (installed field candidate; acceptance pending)

- Normalized LuCI action-button sizing, spacing, wrapping, and mobile behavior
  across account, device, backup, profile, voucher, Events, and DEV surfaces.
- Kept Events as a standalone read-only page and kept DEV limited to future
  feature registration.
- Installed over r93 on the EA8300; post-install preflight, diagnostics, and
  `ndsctl status` passed. Hardware acceptance gates remain open.

## 1.2.0-r93 (installed field candidate; acceptance pending)

- Carries the separated Events/DEV LuCI surfaces and the release-artifact
  isolation guard. Reproducible APK SHA-256:
  `bd63507327ec167dc01075a71ab3d963beb77f09c9b69f797cd6818d9a11bd8a`.
- Guarded deployment upgraded the target from r92 to r93; post-install
  preflight, diagnostics, and `ndsctl status` passed. Physical acceptance
  gates remain open.

## 1.2.0-r92 (superseded; installed predecessor)

- Stabilized authenticated session lifecycle (Candidate implementation; Tested locally, Pending Hardware Validation on physical router):
  - Replaced indiscriminate client iteration in `session-restore.sh reconcile_stale` with `opennds_authenticated_macs` parser, preventing Preauthenticated discovery probes from triggering invalid deauthentications or aborting the reconciliation cycle.
  - Added `COLLATE NOCASE` to MAC address comparisons in `db.sh` (`db_device_get_by_mac`, `db_active_session_count_by_mac`, `db_session_key_by_mac`, `db_session_period_type`, and `db_session_close`), eliminating session drops caused by casing mismatches between openNDS (lowercase) and SQLite (uppercase).
  - Populated `policy_period_start` in `active_sessions` upon session consumption in `db_auth_consume`, preventing redundant and disruptive `opennds_apply_session_policy` invocations on every cron cycle tick.
  - Added retry guard in `ensure_opennds_runtime` before restarting the openNDS service if the daemon process is actively running, preventing transient socket checks from resetting live client connections.
  - Captured return code of `opennds_deauth` in `session-restore.sh`, logging `native_restore_reconciled` on success and `native_restore_reconcile_failed` with `reconcile:deauth_rc=$deauth_rc` on failure without leaking MAC/IP/PIN/tokens.
- Reproducible APK packaging:
  - Updated `tools/build-apk.sh` with deterministic `SOURCE_DATE_EPOCH` enforced from `starter-kit/Makefile` (`PKG_SOURCE_DATE_EPOCH:=1790968682`), rejecting mismatched external values, normalizing file permissions, and clamping mtimes.
  - Added `--verify` flag to run independent builds and verify bit-for-bit identical checksums; clean archive build verified with SHA-256 `a93ab78f04315017c2c4e0fd1d5ac5595024634de8d9d31b5c86aafb0ad655db`.
  - Added regression test `tests/test_apk_reproducibility.sh` and updated GitHub CI to run `tools/build-apk.sh --verify` and fail if hashes differ (a skipped SDK test does not constitute proof of reproducibility).
- Hardened DEV diagnostics:
  - Added pure-shell watchdog timer in `rpc_dev_diagnose` for platforms where external `timeout` binary is unavailable.
  - Added on-target package version discovery via `/usr/lib/open-hotspot/open-hotspot.version` and packaging metadata.
- Reconciled release metadata: r92 is the current installed field candidate; historical checkpoints remain archived and hardware acceptance is still pending.
- Added comprehensive test coverage: extended regression test `tests/test_session_stability.sh`, release consistency contract `tests/test_release_consistency.sh`, and APK reproducibility test `tests/test_apk_reproducibility.sh` (5 Python tests, 28 shell contracts passed; deployment contract 29/29). Cycle stability tests are simulation and contract tests of algorithm branching; end-to-end cycle execution remains a physical router acceptance gate.
- Read-only DEV diagnostics LuCI page (Services → Open-HotSpot → DEV) and RPC methods (`dev_events_list`, `dev_diagnose`).
- Improved diagnostic detail in `cycle.sh` events with safe exit code capture and non-secret context.
- No changes to authentication fail-closed semantics or openNDS contracts. Guarded deployment over r91 completed successfully; all hardware gates remain open pending client-session evidence.

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
