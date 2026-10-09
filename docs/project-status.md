# Open-HotSpot project status

**As of:** 2026-10-03
**Installed field candidate:** Open-HotSpot 1.2.0-r101
**Current source candidate:** Open-HotSpot 1.2.0-r101 (guarded field candidate)
**Previous candidate:** Open-HotSpot 1.2.0-r99
**Target baseline:** Linksys EA8300 / OpenWrt 25.12.5 / `ipq40xx/generic` / openNDS 11.0.0
**Status:** Pre-production acceptance candidate

## Network service-plane safety checkpoint (2026-10-09)

The field evidence shows that the shared service/management bridge must not be
used as the openNDS captive gateway. The source now contains an activation and
preflight service-plane guard: its default `protected` profile refuses that
overlap, while an explicitly acknowledged and future-dated temporary profile
is limited to controlled diagnosis. This is **Implemented** and **Tested** by
local contract tests. The dedicated captive and IoT planes remain **Pending
Hardware Validation**; no router interface, SSID, firewall, or openNDS setting
was changed by this source checkpoint.

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
  when local FAS is activated or an enabled installation is upgraded; r81
  hardens manager-state backup and live-state file permissions; r82 adds the
  conditional dnsmasq-full capability gate and detects/repairs malformed
  OpenWrt Wi-Fi board metadata without embedding a router address; r84 adds
  the executable compatibility bridge for the openNDS 11 reauth-helper path
  mismatch; r85 adds bounded Reassign error reasons instead of flattening all
  safety/database failures to `validation`; r86 applies the exact upstream
  openNDS 11 reauth syntax correction with rollback; r87 contains native
  openNDS `auth_restore` clients that have no manager SQLite session when
  manager Restore is disabled; r88 corrected the optional-file success return in
  the database permission hardening path, and r89 fixes the source-compatible
  reauth bridge that previously bypassed custombinauth on the target; r90
  accepts the explicit native quota-deauth names emitted by the target
  openNDS 11 dispatcher. The installed r92 field candidate (hardware
  validation pending) provides candidate implementation and
  automated regression tests for the reported 3-4 minute client eviction
  (case-insensitive MAC queries, authenticated-only client reconciliation,
  policy_period_start initialization, non-disruptive daemon readiness check;
  cycle stability tests are simulation/contract tests of algorithm logic),
  reproducible APK packaging via deterministic SOURCE_DATE_EPOCH (clean git archive build
  verified with SHA-256 `a93ab78f04315017c2c4e0fd1d5ac5595024634de8d9d31b5c86aafb0ad655db`), safe
  reconciliation error reporting, reconciled release metadata, and a read-only
  DEV diagnostics LuCI page. r100 is now installed on the target and passed
  guarded post-install preflight/diagnostics, but it does not close any
  hardware gate without the required client-session evidence.

## What is not accepted yet

The following are the current release-gate states after the r99 guarded
deployment; the remaining physical gates are still open:

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

1. Close the remaining physical-router gates against the installed r93 field candidate
   while preserving r60/openNDS 10.3.1 as the documented rollback baseline.
   The r93 artifact is installed, post-install checks passed, and the
   separated Events/DEV UI is present; publication remains blocked until the
   remaining physical acceptance gates are recorded.
2. Improve agent governance and traceability without rewriting historical
   evidence.
3. Keep the openNDS 11 compatibility record separate from the r60 rollback
  baseline; r93 belongs on the disposable acceptance slot and remains a
  controlled candidate, not a frozen release. The deployment evidence confirms
  candidate slot 02, openNDS 11.0.0, and r93 installed successfully; fresh
  client-session, quota, restart, and failure-containment evidence remain open.

## Decision rule

No agent may mark a hardware gate complete from source inspection, a mock, or a
browser screenshot alone. Every accepted gate must identify the requirement,
implementation, automated check, field evidence, and release decision.
