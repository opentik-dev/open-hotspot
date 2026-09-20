# Changelog

This file summarizes user-visible and engineering-significant changes. The
release ledger and field checkpoints remain in [`docs/release-history.md`](docs/release-history.md).

## Unreleased

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
