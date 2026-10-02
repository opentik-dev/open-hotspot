# Changelog

This file summarizes user-visible and engineering-significant changes. The
release ledger and field checkpoints remain in [`docs/release-history.md`](docs/release-history.md).

## Unreleased

## 1.2.0-r91 (unpublished working-tree candidate)

- Reconciled release metadata: r90 is explicitly the last field-tested
  acceptance candidate; r91 is marked as unpublished working-tree state in all
  active documentation. Historical version references (r60, r79, r90, etc.)
  remain intact.
- Added `tests/test_release_consistency.sh` contract test to prevent future
  version drift between `starter-kit/Makefile` and active documentation.
- Added read-only DEV diagnostics LuCI page (Services → Open-HotSpot → DEV)
  showing recent admin events (max 50, MAC/IP redacted) and bounded
  `diagnose.sh` output (max 8KB, 30s timeout).
- Added `dev_events_list` and `dev_diagnose` read-only RPC methods with MAC/IP
  sanitization and output limits.
- Improved diagnostic detail in `cycle.sh` events: `session_reconcile_failed`,
  `policy_refresh_failed`, `opennds_not_ready`, `quota_deauth_failed`, and
  `expiry_deauth_failed` now capture exit codes into variables immediately and
  include bounded, non-secret context (period type, window start, exit codes)
  instead of bare MAC addresses.
- No changes to authentication, BinAuth, quota semantics, firewall rules,
  openNDS contracts, or hardware gate statuses. All hardware gates remain open.

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
