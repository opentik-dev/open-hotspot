# Implementation Plan — Open-HotSpot v1.2 Architecture-Corrected

**Inputs**: `spec.md`, `research.md`, `data-model.md`  
**Status**: Phase 0 openNDS gates remain blocking for integration; Phase 1
database/domain foundation is in progress.

## 1. Architecture Summary

```text
                           ┌──────────────────────────┐
                           │        SQLite             │
                           │ identity / policy /       │
                           │ accounting / auth tx      │
                           └────────────┬─────────────┘
                                        │
Client                                  │
  │                                     │
  ▼                                     │
openNDS portal                           │
  │ POST username + PIN                 │
  ▼                                     │
Local FAS/auth handler ── verify ───────┘
  │
  │ create short-lived auth context
  │ + policy snapshot
  ▼
Verified openNDS authorization handoff
  │
  ▼
openNDS enforcement
  │
  └──────────────► BinAuth
                    │
                    ├─ consume/validate auth context
                    ├─ update live session state
                    └─ session-close accounting → SQLite

LuCI ───────────────► management/backend helpers
                         │
                         ├─ account/device/profile/voucher CRUD
                         ├─ force deauth
                         └─ policy refresh

cycle.sh ───────────► rollover / expiry / policy refresh
maintenance.sh ─────► WAL / retention / bounded logs
```

**Critical boundary:** `binauth.sh` never calls `ndsctl`.

## 2. Phase 0 — Target Verification

No production integration code is started before these gates close:

| Gate | Verification | Exit evidence |
|---|---|---|
| A | BinAuth method/args | captured target output/source |
| B | FAS handoff/custom data | working redirect/PoC |
| C | quota return path | measured native enforcement |
| D | ndsctl outside callback | exact help/source + smoke test |
| E | counter mapping | controlled upload/download test |
| F | local FAS runtime | working local login |
| G | PBKDF2 | target command/library test + benchmark |
| H | dnsmasq-full need | feature-specific result |
| I | restart/auth-restore | reboot/restart test |

### Phase 0 safety rule

Do not perform an implicit package upgrade. Any package installation/replacement
must be an explicit step after version/package availability has been recorded.

## 3. Runtime Components

### 3.1 Local FAS/authentication handler

Responsibilities:

1. parse and validate portal POST data
2. locate account
3. verify PIN
4. check account status and hard expiry
5. resolve profile
6. calculate current aggregate remaining budget
7. atomically validate/prepare the simultaneous-device decision
8. create a short-lived `auth_transaction`
9. return the verified openNDS authorization handoff using the Phase 0 contract

It must not log the PIN.

### 3.2 `binauth.sh`

Responsibilities:

- parse the exact method-specific BinAuth arguments
- for authorization callbacks, consume/validate the short-lived auth context
- associate the MAC with the already-verified account
- establish/update `active_sessions`
- for deauth/session-close methods, create one `usage_events` row
- aggregate only a newly inserted event
- close/update `active_sessions` and `devices`

Forbidden:

- `ndsctl`
- firewall manipulation
- periodic polling
- account lookup by MAC as proof of identity

### 3.3 `opennds.sh`

A single backend adapter for all openNDS control operations outside BinAuth.
It hides version-specific command syntax behind verified functions.

Example interface:

```text
opennds_validate_config
opennds_reload
opennds_deauth <mac>
opennds_apply_session_policy <mac> <policy>
opennds_live_clients
```

The final implementation of each function is blocked until Phase 0 verifies
whether the operation is supported and what syntax/units it requires.

### 3.4 `cycle.sh`

Runs every configured interval (minimum 60 s) under `flock -n`.

Only:

- open due periods
- close expired periods
- perform hard-expiry enforcement
- apply necessary live policy refresh through `opennds.sh`

It must not perform daily maintenance or unrelated scans.

### 3.5 `maintenance.sh`

Runs daily under `flock -n`:

- WAL checkpoint
- prune closed history according to retention
- prune expired `auth_transactions`
- prune old admin events
- rotate bounded logs

## 4. Authentication State Machine

```text
START
  ↓
Validate request
  ↓
Lookup account
  ↓
Verify PIN
  ├─ fail → DENY
  ↓
Check status/expiry
  ├─ fail → DENY
  ↓
Resolve current period + policy
  ↓
Check remaining budget
  ├─ exhausted → DENY
  ↓
Atomic device/session admission
  ├─ limit reached → DENY
  ↓
Create auth_transaction
  ↓
Verified openNDS handoff
  ↓
OPENNDS
  ↓
BinAuth consumes context
  ↓
ACTIVE SESSION
```

The exact openNDS handoff is selected only after Gate B/C.

## 5. Accounting State Machine

```text
BinAuth deauth/session-close
        ↓
parse method-specific args
        ↓
resolve event/session identity
        ↓
BEGIN IMMEDIATE
        ↓
INSERT usage_events ON CONFLICT(event_key) DO NOTHING
        │
        ├─ duplicate → COMMIT / no aggregate change
        │
        └─ new
             ↓
        split usage at period boundary if required
             ↓
        update usage_periods
             ↓
        close active_session
             ↓
        update device last_seen
             ↓
        COMMIT
```

## 6. Period Management

Period boundaries are calculated from router local timezone but stored as UTC.

For a period-spanning session, the accounting helper must calculate the overlap
with each period:

```text
segment = [max(session_start, period_start),
           min(session_end, period_end)]
```

Traffic counters require a verified allocation method. If openNDS supplies only
whole-session cumulative counters, the implementation must define and test the
allocation rule before claiming exact boundary accounting.

## 7. Quota Policy Adapter

The manager keeps policy in normalized internal units:

```text
seconds
bytes
kbps
```

`opennds.sh` converts these values to the exact target openNDS units.

This prevents openNDS version-specific units from leaking into the database model.

## 8. Device Admission

The simultaneous-device limit must be enforced as a database transaction using
`active_sessions`.

A device that is already the account's active session does not consume a second
slot merely because the portal retries authentication. A genuinely new active
session does consume one slot.

If the target openNDS build cannot provide enough session identity information to
make this atomic, the limitation must be recorded in Phase 0 and the requirement
must not be silently weakened.

## 9. Setup State Machine

```text
PRECHECK
  ↓
BACKUP
  ↓
PACKAGE PLAN
  ↓
INSTALL/VERIFY REQUIRED PACKAGES
  ↓
DB INIT/MIGRATE
  ↓
OPENNDS CONFIG VALIDATE
  ↓
INSTALL/SELECT PORTAL TEMPLATE
  ↓
START/RELOAD SERVICES
  ↓
HEALTH CHECK
  ↓
READY
```

Every state is idempotent and records success/failure. A restart resumes from
the first incomplete state.

`dnsmasq-full` is not included in the package plan unless a selected feature
requires it.

## 10. Package Layout

```text
luci-app-open-hotspot/
├── Makefile
├── root/
│   ├── etc/config/open-hotspot
│   ├── etc/init.d/open-hotspot
│   ├── etc/uci-defaults/40-open-hotspot
│   ├── usr/lib/open-hotspot/
│   │   ├── schema.sql
│   │   ├── db.sh
│   │   ├── admin.sh
│   │   ├── quota.sh
│   │   ├── pbkdf2.sh
│   │   ├── opennds.sh
│   │   ├── binauth.sh
│   │   ├── period.sh
│   │   ├── cycle.sh
│   │   ├── maintenance.sh
│   │   └── validate.sh
│   ├── www/cgi-bin/hotspot-login
│   ├── usr/share/open-hotspot/templates/
│   ├── usr/libexec/rpcd/open_hotspot
│   └── usr/share/rpcd/acl.d/luci-app-open-hotspot.json
└── luasrc/
    ├── controller/open-hotspot.lua
    ├── model/cbi/open-hotspot/
    │   ├── setup.lua
    │   ├── accounts.lua
    │   ├── devices.lua
    │   ├── profiles.lua
    │   ├── vouchers.lua
    │   ├── status.lua
    │   └── history.lua
    └── view/open-hotspot/
```

## 11. Dependency Strategy

Core runtime requirements are only those proven necessary by the selected
implementation. Expected core components are:

- openNDS
- SQLite CLI/library
- LuCI base components
- the verified crypto/KDF facility

`dnsmasq-full` is feature-dependent.

`firewall4` is part of the OpenWrt 25.12 baseline but is verified, not blindly
reconfigured by Open-HotSpot.

## 12. Security Boundaries

All external input is classified:

| Input | Validation |
|---|---|
| username | strict allow-list + normalization |
| PIN | length/policy validation; never SQL-escaped into logs as plaintext |
| MAC | strict canonical MAC parser |
| voucher | strict generated-code format |
| integer limits | decimal integer/range validation |
| hostname/detail | length limit + SQL escaping |
| UCI options | allow-listed enum/range |
| auth handoff key | opaque generated value, never user supplied |

`db.sh` must honestly document that shell SQL uses validation + escaping, not
compiled prepared-statement binding.

## 13. LuCI Design

CBI pages are thin UI layers. They call backend helpers for transactions and
validation rather than duplicating security-sensitive SQL in Lua.

Dashboard data is split:

```text
SQLite → persistent account/profile/usage state
openNDS → live connected/session state
```

No dashboard polling continues when the page is closed.

## 14. Testing Strategy

### Unit/smoke

- schema migration
- KDF hash/verify
- username/MAC validation
- quota calculations
- voucher atomic redemption
- usage event deduplication

### Integration

- portal → FAS → openNDS authorization
- rate/volume/time policy
- BinAuth callback parsing
- session close accounting
- device admission race
- period rollover
- period-spanning session accounting

### Failure tests

- SQLite temporarily unavailable
- BinAuth exits non-zero
- cycle job killed midway
- maintenance job killed midway
- router reboot
- openNDS restart
- setup interrupted during package transition

## 15. Constitution Traceability

| Principle | Implementation consequence |
|---|---|
| Minimal footprint | no RADIUS, no daemon, native openNDS enforcement |
| Stability | no BinAuth `ndsctl`, no busy loop, locked jobs |
| Single source of truth | SQLite for persistent state; UCI for manager config |
| Native enforcement | openNDS owns rate/volume/session enforcement |
| Zero-trust input | allow-lists, validation, bounded text, no secrets in logs |
| Idempotent/observable | transactions, unique event keys, bounded audit records |
| LuCI-native UX | CBI pages, thin UI/backend boundary |
