# Architecture overview

Open-HotSpot is a local management and policy layer around openNDS. The
system deliberately keeps captive-portal enforcement in openNDS and stores
identity, policy, accounting, and administration state locally in SQLite.

```text
Client
  ↓
openNDS captive portal
  ↓
Local FAS ── credential and policy decision ── SQLite
  ↓
Verified openNDS authorization handoff
  ↓
openNDS native session/rate/volume enforcement
  ↓
BinAuth callback ── idempotent usage event ── SQLite
  ↓
LuCI / RPC administration
```

## Ownership boundaries

| Component | Owns | Must not own |
|---|---|---|
| openNDS | Captive portal, live session enforcement, native rate and volume limits | Local account database or application UI |
| Local FAS | Username/PIN verification, policy lookup, authorization context | Direct firewall enforcement or plaintext credential forwarding |
| BinAuth | Method-specific callback parsing, session correlation, close accounting | `ndsctl`, firewall changes, polling, or MAC-only identity proof |
| SQLite/domain layer | Accounts, devices, profiles, vouchers, periods, sessions, usage events | Assumptions about unverified target contracts |
| LuCI/RPC | Administration and read-only status views | Unbounded package work or hidden destructive actions |
| Maintenance helpers | Rollover, expiry, retention, restore, and verified control operations | Replacing openNDS's native enforcement engine |

## Failure model

New identity decisions fail closed when identity, policy, or credential state
cannot be verified. Existing authorized openNDS sessions retain their last
applied state when the manager, BinAuth, or maintenance path fails.

## Compatibility boundary

The exact openNDS version, callback arguments, FAS handoff, quota units, and
`ndsctl` syntax are target contracts. They are recorded in the research,
versioned adapter, and release-evidence documents. Unknown or unverified
contracts must block activation rather than being guessed.

For the current r112 state and unresolved gates, see
[`current-state.md`](../current-state.md), [`release-gates.md`](../release-gates.md),
and [`release-acceptance-matrix.md`](../release-acceptance-matrix.md).
