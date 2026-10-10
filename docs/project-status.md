# Open-HotSpot project status

**As of:** 2026-10-10
**Installed field candidate:** Open-HotSpot 1.2.0-r112
**Current source candidate:** Open-HotSpot 1.2.0-r112 (openNDS 11 UCI-layout correction)
**Previous candidate:** Open-HotSpot 1.2.0-r111
**Target baseline:** Linksys EA8300 / OpenWrt 25.12.5 / `ipq40xx/generic` / openNDS 11.0.0
**Status:** Pre-production acceptance candidate

## Network service-plane safety checkpoint (2026-10-09)

The field evidence shows that the shared service/management bridge must not be
used as the openNDS captive gateway. The source now contains an activation and
preflight service-plane guard: its default `protected` profile refuses that
overlap, while an explicitly acknowledged and future-dated temporary profile
is limited to controlled diagnosis. This is **Implemented** and **Tested** by
local contract tests. r112 is installed on the target and confirms the target
openNDS 11 `setup` section resolves to the dedicated `br-hotspot` bridge. The
earlier shared-LAN U1 attempt was rolled back; no service-port exception has
been added. The remaining multi-plane, pre-auth denial, post-auth service,
rollback, and IoT gates remain **Pending Hardware Validation**.

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
  The installation, integration, and troubleshooting chain is centralized in
  the runbooks, release matrix, and operational ledger. Historical r70–r111
  implementation details remain in the release history and are not repeated
  in the current status page.

## What is not accepted yet

The following are the current release-gate states for r112; the remaining
physical gates are still open:

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

The target-side Wi-Fi repair is verified at the router boundary; it does not
close the phone captive-portal or clean-hardware gates until a phone sees the
SSID and completes the recorded acceptance flow.

The 2026-10-02 read-only audit reached the supplied EA8300 management path and
found a current preflight pass but a stale UCI `setup_state=PREFLIGHT_FAILED`.
The target log still contains dnsmasq reload, preemptive-MAC, and routing
configuration errors, while the recurring reconciliation and policy-refresh
events are not exposed in LuCI. The observed authenticated client remained
authenticated past four minutes, so the reported eviction is not yet
reproduced under a controlled account/profile test. The release gates remain
open.

## Active workstreams

1. Close the remaining physical-router gates against the installed r112 field candidate
   while preserving r60/openNDS 10.3.1 as the documented rollback baseline.
   The r112 artifact is installed, post-install checks passed, and publication remains blocked until the
   remaining physical acceptance gates are recorded.
2. Improve agent governance and traceability without rewriting historical
   evidence.
3. Keep the openNDS 11 compatibility record separate from the r60 rollback
  baseline; r112 belongs on the disposable acceptance slot and remains a
  controlled candidate, not a frozen release. The deployment evidence confirms
  candidate slot 02, openNDS 11.0.0, and r112 installed successfully; fresh
  client-session, quota, restart, and failure-containment evidence remain open.

## Decision rule

No agent may mark a hardware gate complete from source inspection, a mock, or a
browser screenshot alone. Every accepted gate must identify the requirement,
implementation, automated check, field evidence, and release decision.
