# Open-HotSpot project status

**As of:** 2026-09-22
**Product candidate:** Open-HotSpot 1.2.0-r79
**Target baseline:** Linksys EA8300 / OpenWrt 25.12.5 / `ipq40xx/generic` / openNDS 11.0.0
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
- The installation, integration, and troubleshooting chain is centralized in
  [`installation-and-integration-runbook.md`](installation-and-integration-runbook.md),
  [`integration-gap-register.md`](integration-gap-register.md), and the
  read-only `/usr/lib/open-hotspot/diagnose.sh` command shipped in r70; r71
  adds versioned openNDS adapter contracts and stale-session diagnostics. r74
  unifies period/renewal handling across FAS, BinAuth, cycle, and restore and
  hardens manager-side SQLite invocation defaults; r75 adds zero-client stale
  manager-session reconciliation; r76 expires abandoned pending FAS
  transactions during cycle/maintenance; r77 resolves target-specific live
  deauthentication through IP lookup; r78 correlates the target's empty
  deauth custom marker to the active session; r79 enables the manager service
  when local FAS is activated or an enabled installation is upgraded.

## What is not accepted yet

The following are the current release-gate states after the r78 physical
acceptance run:

| Gate | Current state | Required proof |
|---|---|---|
| T003 | Verified | FAS redirect, custom data, and secure local login on target |
| T006 | Pending Hardware Validation | Controlled upload/download counter mapping and cutoff |
| T011 | Partial / Verified restore slice | Separate openNDS restart and router reboot; disabled restore reconciliation and enabled automatic restore after client traffic; full dedup/restart matrix remains |
| T012 | Verified — primary physical path | Portal → FAS → authorization → BinAuth → close → SQLite; duplicate callback remains automated-only |
| T052/T087 | Pending Hardware Validation | Interrupted setup/retry, dependency health, and package recovery |
| T086 | Pending Hardware Validation | Existing sessions preserved while new decisions fail closed |
| T088/T090 | Pending Hardware Validation | Complete quickstart and release freeze evidence |

`Implemented` and `Tested` do not mean `Accepted`. The authoritative gate
register is [`release-gates.md`](release-gates.md); the evidence workflow is in
[`factory-reset-acceptance-runbook.md`](factory-reset-acceptance-runbook.md).

## Active workstreams

1. Close the remaining physical-router gates against the r79 candidate while
   preserving r60/openNDS 10.3.1 as the documented rollback baseline.
2. Improve agent governance and traceability without rewriting historical
   evidence.
3. Keep the openNDS 11 compatibility record separate from the r60 rollback
  baseline; r79 is installed on the disposable acceptance slot, but it is
   not production-accepted until the physical gates close.

## Decision rule

No agent may mark a hardware gate complete from source inspection, a mock, or a
browser screenshot alone. Every accepted gate must identify the requirement,
implementation, automated check, field evidence, and release decision.
