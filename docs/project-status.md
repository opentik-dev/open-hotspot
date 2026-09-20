# Open-HotSpot project status

**As of:** 2026-09-20  
**Product candidate:** Open-HotSpot 1.2.0-r60  
**Target baseline:** Linksys EA8300 / OpenWrt 25.12.5 / `ipq40xx/generic` / openNDS 10.3.1-r3  
**Status:** Pre-production acceptance candidate

## What is established

- The architecture keeps openNDS as the captive-portal and traffic-enforcement
  engine; Open-HotSpot owns local identity, policy, accounting, and LuCI.
- SQLite schema, migrations, quota arithmetic, period handling, voucher
  atomicity, duplicate-event protection, PBKDF2 handling, FAS/BinAuth
  boundaries, and the LuCI/RPC layer have automated coverage.
- BinAuth does not call `ndsctl`; administrative control is isolated in the
  adapter/maintenance path.
- The EA8300 target and its current openNDS contract are recorded in
  `specs/001-open-hotspot/research.md` and `quickstart.md`.
- The two-slot router layout is treated as rollback capability, not shared
  application state.

## What is not accepted yet

The following remain release blockers until real-router evidence is attached:

| Gate | Current state | Required proof |
|---|---|---|
| T003 | Pending Hardware Validation | FAS redirect, custom data, and secure local login on target |
| T006 | Pending Hardware Validation | Controlled upload/download counter mapping and cutoff |
| T011 | Partial | Separate openNDS restart and router reboot, restore policy, and usage deduplication |
| T012 | Pending Hardware Validation | Portal → FAS → authorization → BinAuth → close → SQLite |
| T052/T087 | Pending Hardware Validation | Interrupted setup/retry, dependency health, and package recovery |
| T086 | Pending Hardware Validation | Existing sessions preserved while new decisions fail closed |
| T088/T090 | Pending Hardware Validation | Complete quickstart and release freeze evidence |

`Implemented` and `Tested` do not mean `Accepted`. The authoritative gate
register is [`release-gates.md`](release-gates.md); the evidence workflow is in
[`factory-reset-acceptance-runbook.md`](factory-reset-acceptance-runbook.md).

## Active workstreams

1. Close the remaining v1.2 physical-router gates against the r60 baseline.
2. Improve agent governance and traceability without rewriting historical
   evidence.
3. Evaluate openNDS 11 in an isolated compatibility track. No v11 package is
   installed on the acceptance router until its contract and rollback proof
   are complete.

## Decision rule

No agent may mark a hardware gate complete from source inspection, a mock, or a
browser screenshot alone. Every accepted gate must identify the requirement,
implementation, automated check, field evidence, and release decision.
