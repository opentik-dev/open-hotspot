# Feature Specification: Open-HotSpot — Local LuCI Hotspot Manager

**Feature branch**: `001-open-hotspot`  
**Version**: `1.2 Architecture-Corrected`  
**Status**: Architecture baseline — implementation remains gated by Phase 0  
**Target**: OpenWrt 25.12.x + openNDS resolved from the target feed

## 1. Product Scope

Open-HotSpot is a lightweight, local-only LuCI manager for one OpenWrt
router running openNDS. It provides account/device management, reusable
quota/rate profiles, voucher redemption, usage accounting, portal templates,
and operational controls without introducing FreeRADIUS, RADIUSdesk, an
external database, a cloud service, or a permanent custom traffic collector.

The architectural rule is strict:

> **openNDS remains the captive-portal and traffic-enforcement engine;
> Open-HotSpot is the local policy, identity, accounting, and management
> layer.**

v1.2 corrects the previous design by removing all `ndsctl` calls from
BinAuth. BinAuth is event-driven accounting/authorization integration only.
Administrative or maintenance calls to `ndsctl`, if required by the verified
openNDS build, occur outside BinAuth through explicitly locked helper jobs.

## 2. Design Principles

1. Reuse openNDS native session, volume, and rate enforcement.
2. Keep persistent application state in SQLite; keep manager configuration in UCI.
3. Keep authentication and authorization distinct from accounting callbacks.
4. Never call `ndsctl` from BinAuth.
5. Do not run a custom byte-counting daemon.
6. New authentication fails closed if identity/policy state cannot be verified.
7. Existing openNDS sessions survive manager failure under their last applied state.
8. Never manipulate nftables directly for per-client quota enforcement.
9. Prefer LuCI CBI and POSIX shell over a new JavaScript build system.
10. Any openNDS behavior not proven on the resolved target build is a Phase 0 gate,
    not an implementation assumption.

## 3. User Scenarios

### US-1 — Guided setup (P1)
Administrator opens the setup wizard on OpenWrt 25.12.x. The wizard checks
compatibility, prepares required packages, initializes the database, validates
openNDS integration, installs a selected portal template, and reports the
result of every step.

The wizard must not blindly replace `dnsmasq`; `dnsmasq-full` is optional and
is installed only when a selected feature actually requires it.

### US-2 — Account login (P1)
Administrator creates account `ahmed` and assigns a profile such as
`2h / 500 MB / daily / 2 devices`. Ahmed submits username + PIN on the local
portal. The local FAS/authentication path verifies the PIN against SQLite.
The PIN is never sent to openNDS as a credential.

After successful verification, the implementation uses the **verified
openNDS-supported authorization handoff** established by Phase 0. The handoff
carries an authenticated account identity/policy context; it is not a raw
MAC lookup.

### US-3 — Multiple devices (P1)
An account may own multiple registered devices. A device is identified by MAC.
The account's profile defines the maximum number of **simultaneously connected**
devices in v1.2. A new authentication is rejected when accepting it would exceed
that limit. The implementation must enforce this atomically using the verified
live-session/accounting state; it must not depend on a best-effort UI count.

### US-4 — Quota enforcement (P1)
Time and upload/download data budgets are aggregated across all active and
closed sessions for the account's current period. openNDS enforces the
per-session ceilings using its native mechanisms. Enforcement precision is
bounded by openNDS's documented accounting/check interval; v1 does not claim
zero-latency cutoff.

### US-5 — Administration (P1)
Administrator can suspend/enable accounts, change profile/expiry, force-deauth
a device, remove or block a device, renew a period, and inspect usage history.
Destructive actions require confirmation.

### US-6 — Voucher self-service (P2)
Administrator generates voucher batches. A voucher is bound to a profile and
validity period. Redemption is an atomic one-time operation; concurrent
redemption of the same code yields exactly one success.

### US-7 — Period rollover (P2)
At a period boundary, the manager closes the old aggregate, creates the next
period, and applies any required policy change to live sessions using a
verified openNDS control path outside BinAuth. v1.2 does not promise an exact
calendar-boundary reset when the enforcement mechanism only permits interval-
based reapplication.

### US-8 — Portal branding (P3)
Administrator chooses from bundled portal templates, including an Arabic RTL
template, without manually editing openNDS files.

## 4. Functional Requirements

### Setup and dependencies

- **FR-001**: Setup must perform preflight checks before modifying packages,
  configuration, or services.
- **FR-002**: The wizard must verify the exact package names and versions
  available for the target OpenWrt 25.12.x architecture before installation.
- **FR-003**: `dnsmasq-full` is **not a mandatory core dependency**. It may be
  installed only when a selected openNDS feature requires it. If a swap is
  required, the replacement must be staged and verified before the base package
  is removed.
- **FR-004**: Setup must initialize/migrate SQLite idempotently and validate
  openNDS configuration before declaring READY.

### Accounts, credentials, and devices

- **FR-010**: Administrator can create/edit/delete accounts with username,
  PIN, profile, status, and optional hard expiry.
- **FR-011**: Account identity is independent of MAC address.
- **FR-012**: PINs are stored only as a salted, iterated password-derived value
  using the selected KDF defined by Phase 0. Raw single-round hashes are forbidden.
- **FR-013**: The plaintext PIN must never be stored, logged, passed to openNDS,
  or included in audit/event details.
- **FR-014**: A device has one normalized MAC address and belongs to one account.
  A blocked device cannot authenticate until unblocked.
- **FR-015**: `max_devices` means **maximum simultaneously connected devices**,
  not maximum historical registrations.
- **FR-016**: Renew starts a fresh aggregate quota window at the current UTC
  instant, preserves prior usage history, deauthenticates currently active
  devices through the verified adapter, and records an administrative event.
- **FR-017**: MAC reassignment is explicit and audited; it is rejected while
  the device has a live session, requires an active target account, and is
  never performed implicitly by authentication.

### Profiles and quotas

- **FR-020**: A profile contains period type, aggregate time budget, aggregate
  upload/download data budgets, native upload/download rate limits, and the
  simultaneous-device limit.
- **FR-021**: Period types are `hourly`, `daily`, `monthly`, `yearly`, and `none`.
- **FR-022**: Stored time is seconds; stored traffic counters are bytes. Values
  sent to openNDS use the units required by the verified target contract.
- **FR-023**: A zero budget means unlimited for that dimension.
- **FR-024**: Remaining budget is calculated from the account's aggregate current
  period, not separately per device.
- **FR-025**: If either a time or data budget is exhausted, no new authorization
  may be granted and an active session must be subject to openNDS's native
  ceiling behavior. Exact cutoff precision is documented from Phase 0 testing.

### Authentication and authorization boundary

- **FR-030**: The portal authentication path verifies username + PIN locally.
- **FR-031**: After verification, the portal passes only the minimum identity /
  policy context required by the verified openNDS integration contract.
- **FR-032**: The system must not identify an account from MAC alone.
- **FR-033**: BinAuth must not call `ndsctl`, directly manipulate firewall rules,
  or implement a polling loop.
- **FR-034**: BinAuth must process the exact argument layout for the resolved
  openNDS build. `auth_client` and deauthentication methods are distinct and
  must never share a guessed positional parser.
- **FR-035**: If the database or identity context is unavailable during a new
  authentication decision, the authentication fails closed. An already
  authorized session is not proactively destroyed solely because the manager
  failed.

### Accounting

- **FR-040**: Deauthentication/session-close events received by BinAuth are
  converted to aggregate usage exactly once.
- **FR-041**: Idempotency is enforced by a unique event key in SQLite before
  updating aggregates.
- **FR-042**: Raw openNDS session counters are retained in `usage_events` for
  audit/debugging before aggregation.
- **FR-043**: If a session crosses a period boundary, accounting must split the
  elapsed time/traffic at the boundary or use a verified event model that
  produces equivalent per-period totals. The implementation may not assign the
  whole session to one period merely because it ended there.
- **FR-044**: Usage survives router reboot and openNDS restart without duplicate
  aggregation.
- **FR-045**: The administrator can enable or disable manager-owned live-session
  restoration from LuCI. When enabled, restoration runs outside BinAuth,
  revalidates the active account and current SQLite policy, uses the verified
  native openNDS authorization path, and never depends on a client IP address.
  Disabled mode requires a fresh portal login after restart.

### Administration and maintenance

- **FR-050**: Administrator can force-deauth a device through a helper path that
  is outside BinAuth and uses the verified openNDS command/API contract.
- **FR-051**: Period rollover, expiry sweeps, and other scheduled correctness
  work run at no more than once per configured interval, with a minimum interval
  of 60 seconds and `flock` protection.
- **FR-052**: Daily maintenance handles WAL checkpointing, retention, and logs.
- **FR-053**: Maintenance failure must not alter openNDS's already-applied live
  authorization state.

### Vouchers

- **FR-060**: Vouchers have unique codes and states `unused`, `redeemed`, or
  `revoked`.
- **FR-061**: Redemption is an atomic conditional state transition and records
  the resulting account and timestamp.
- **FR-062**: A redeemed or revoked voucher cannot be reused.

### UI and backup

- **FR-070**: LuCI CBI provides setup, accounts, devices, profiles, vouchers,
  dashboard, and history views.
- **FR-071**: Live dashboard queries openNDS live state on demand only while the
  relevant page is open; SQLite remains the persistent source of truth.
- **FR-072**: Export/import covers the manager database and UCI configuration,
  with validation before replacement.
- **FR-073**: At least two portal templates ship, including English and Arabic RTL.

## 5. Non-Functional Requirements

- **NFR-001 — Stability**: no custom background loop; scheduled jobs are ≥60 s,
  locked, bounded, and idempotent.
- **NFR-002 — Footprint**: manager code remains small and auditable.
- **NFR-003 — Responsiveness**: LuCI rendering never waits on package installation,
  database migration, or other unbounded operations.
- **NFR-004 — Compatibility**: target OpenWrt 25.12.x and its supported LuCI stack.
- **NFR-005 — Security**: credential storage uses the verified KDF; input validation
  is allow-list based; secrets never appear in logs.
- **NFR-006 — Recoverability**: setup is restartable after interruption and never
  assumes a pristine router after the first successful step.
- **NFR-007 — Observability**: setup, authentication failures, administrative
  actions, and accounting anomalies have bounded diagnostic records without
  exposing PINs or other secrets.

## 6. Data Semantics

### Account vs Device

```text
Account 1 ─────── N Device
   │
   └────────────── N UsagePeriod
```

An account owns policy and aggregate quota. A device is merely an endpoint
belonging to the account.

### Quota calculation

For the active period:

```text
remaining_time = max(0, time_limit_s - seconds_used)
remaining_up   = max(0, upload_limit_b - bytes_up)
remaining_down = max(0, download_limit_b - bytes_down)
```

A rate limit is a native per-session ceiling, not an aggregate usage budget.

### Period boundary

Period boundaries use the router's configured timezone to determine calendar
windows, then persist timestamps in UTC. A session spanning a boundary must be
accounted across both periods.

## 7. Failure Semantics

| Situation | New authentication | Existing authorized session |
|---|---|---|
| SQLite temporarily unavailable | Deny/abort authorization | Keep last openNDS state |
| BinAuth invocation fails | Do not revoke by manager action | Keep last openNDS state |
| cycle job fails | No new scheduled policy change | Keep last openNDS state |
| maintenance job fails | No effect on auth state | No effect |
| openNDS itself fails | Controlled by openNDS/system recovery | Controlled by openNDS/system recovery |

This is intentionally **fail-closed for new identity decisions and fail-safe
for already-applied openNDS sessions**.

## 8. Out of Scope for v1.2

- RADIUS/FreeRADIUS/RADIUSdesk integration
- multi-router federation or roaming
- cloud services
- payment/billing gateways
- 802.1X
- per-application shaping
- custom nftables quota accounting
- high-frequency traffic collector
- mobile application
- external API as a required runtime dependency

## 9. Success Criteria

- **SC-001**: A test account cannot obtain a new session after its aggregate
  period budget is exhausted.
- **SC-002**: Native openNDS enforcement reaches the measured cutoff within the
  verified target interval/contract; the test records the observed bound.
- **SC-003**: Reboot/restart does not double-count a previously processed session.
- **SC-004**: Manager process failure does not intentionally disconnect already
  authorized clients.
- **SC-005**: The BinAuth script contains no `ndsctl` invocation.
- **SC-006**: Two concurrent reports for the same session produce one aggregate
  accounting event.
- **SC-007**: A profile's simultaneous-device limit is enforced without allowing
  an N+1 race.
- **SC-008**: Voucher double redemption produces one success and one rejection.
- **SC-009**: Period-spanning sessions produce correct totals in both periods.
- **SC-010**: Setup can be interrupted and safely resumed without leaving the
  router in an unrecoverable DNS/DHCP/openNDS state.

## 10. Phase 0 Release Gate

No production implementation is authorized until the following are verified
against the **actual openNDS package/build selected for the target OpenWrt
architecture**:

1. BinAuth method names and exact argument contracts.
2. FAS/authentication redirect and custom-variable contract.
3. The supported place to return session/rate/volume ceilings.
4. `ndsctl auth` syntax/units if needed outside BinAuth.
5. `ndsctl deauth` syntax if used by administration.
6. Mapping of openNDS incoming/outgoing counters to upload/download.
7. Local FAS runtime prerequisites.
8. KDF availability on the target OpenWrt crypto package.
9. Whether any planned feature actually requires `dnsmasq-full`.
10. Reboot/auth-restore behavior relevant to live sessions.

The implementation must record the resolved version and the evidence used to
close each gate in `research.md` and `quickstart.md`.
