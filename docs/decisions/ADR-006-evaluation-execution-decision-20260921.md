# ADR-006 — Evaluation report execution decision

**Date:** 2026-09-21  
**Decision:** Execute the report's confirmed P0/P1 engineering corrections in
the next source candidate; do not declare the product accepted until the named
physical-router gates close.

## Decision summary

The evaluation is accepted as an engineering input, not as release evidence.
The report correctly identifies that the project has a strong architecture but
that the runtime chain is not yet proven end to end. The current candidate is
therefore r74, a source-tested correction checkpoint, not a production release.

## Executed in r74

- The adapter contract test resolves the repository's versioned adapters in a
  clean checkout and no longer depends on a target filesystem path.
- FAS calls the packaged period helper used by the shell paths. BinAuth,
  cycle, and reboot restore all use the effective window including
  `renewed_at`.
- ISO renewal timestamps are normalized before parsing so the contract works
  with BusyBox/OpenWrt date behavior.
- Manager-side SQLite calls sourced through `db.sh` use a five-second timeout
  and foreign-key enforcement consistently.
- Account suspension/deletion, device blocking, and profile changes now request
  adapter-backed deauthentication for affected live MACs; BinAuth remains the
  only close/accounting callback.
- The gap register now records these failures and the evidence requirement for
  each one.

## Evidence obtained

The repository unit, shell, quota, adapter, FAS, BinAuth, period, and full
contract suite passed. PHP syntax passed, the APK was rebuilt from source, and
the period/BinAuth checks also passed with BusyBox `date` selected in `PATH`.
These are `Tested` results; they are not physical-router `Verified` results.
The r74 APK SHA-256 is
`9d318a81aea8038fa36d77a8e137d0635793e290032f790f39935cbb792c2da2`.

## Still blocking delivery

T003/T012 still need a disposable-client close/accounting transcript; T006
needs controlled counter and quota-cutoff evidence; T011 needs separate
openNDS-restart and router-reboot evidence including deduplication and the
configured restore policy; T052/T087 need interrupted setup/retry evidence;
T086 needs failure-containment evidence; T088/T090 need the complete clean
hardware acceptance. No report, screenshot, mock, or source test closes these
gates.

## Rollback

Keep Open-HotSpot r60 with openNDS 10.3.1-r3 as the rollback baseline. Install
r74 only on the disposable candidate slot after its APK checksum is recorded;
use the known SSH-plus-tar transport because the target has no `sftp-server`.
