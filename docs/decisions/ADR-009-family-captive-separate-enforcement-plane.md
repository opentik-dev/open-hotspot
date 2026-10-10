# ADR-009: Family Captive uses a separate enforcement plane

**Status:** Accepted for implementation — target activation blocked until the
multi-instance adapter is verified
**Date:** 2026-10-10
**Supersedes:** nothing. ADR-007 remains the production topology baseline and
ADR-008 remains an isolated shared-LAN experiment only.

## Context

The household needs one management experience for accounts, profiles, quotas,
devices, vouchers, and portal branding, while retaining two materially
different client policies:

- family devices need Internet subject to account limits and selected home
  services after login;
- guest devices need Internet subject to the same account/profile model but
  must never inherit family access to NAS, PBX, cameras, LuCI, SSH, or the
  tailnet.

The acceptance router currently has one openNDS configuration section and one
active captive gateway on `br-hotspot`. A single openNDS instance cannot turn
the global `authenticated_users` rule set into per-account roles. Adding an
SSID, bridge, or firewall forwarding before a separate verifier exists would
create a network that appears governed but is not actually captive-controlled.

Target inspection on 2026-10-10 confirms that the installed OpenWrt init
service starts one direct `opennds -f` procd process and does not iterate UCI
sections. Therefore adding a second `config opennds` section is not an
implementation of this decision.

## Decision

Use one Open-HotSpot **control plane** and two separate captive **enforcement
planes**:

```text
                   SQLite accounts / profiles / usage / devices
                                      │
                         Open-HotSpot LuCI + local FAS
                                      │
                ┌─────────────────────┴─────────────────────┐
                │                                           │
       Guest openNDS instance                       Family openNDS instance
          br-hotspot / Guest                         br-family / Family
                │                                           │
       Internet only after login              Internet + explicit home services
```

`br-lan` remains the management/service plane. `br-guest` remains a transit
plane and is not repurposed. Tailscale remains an explicitly filtered overlay
to approved management/service destinations; it is neither an openNDS
exception nor a path from guests into the family/service plane.

The feature starts fail-closed. `family-captive-preflight.sh check` refuses
activation unless a distinct device/network is declared, a verified
multi-instance adapter is selected, and a separate openNDS instance is
present. Even then it remains blocked until the runtime adapter contract is
implemented and field-proven.

## Five mandatory isolation boundaries

The compatibility project is accepted only when all five boundaries below have
automated evidence and separate disposable-router evidence. A successful login
or a second running process alone is not sufficient.

| Boundary | Required implementation | Acceptance evidence |
|---|---|---|
| Control socket and runtime | Each daemon has its own runtime directory, PID file, control socket, log mount/path, and `ndsctl` wrapper. No path may default to or overwrite the Guest instance. | Start/restart each instance in both orders; prove each wrapper addresses only its own daemon and stopping one leaves the other session alive. |
| FAS identity and ports | Each captive bridge has an IPv4 gateway identity. FAS receives a validated, explicit plane identity derived from the verified gateway context; its listener/redirect identity cannot collide. Keys and client tokens remain redacted. | A disposable client on each plane reaches the correct portal and its authentication transaction is attributed to its own plane. |
| Session and accounting | SQLite auth transactions, active sessions, usage events, and deauthentication correlation carry a validated `plane_id`. BinAuth remains event-driven and must not call `ndsctl`, manipulate firewall rules, or poll. | Same account/device lifecycle is tested across both planes; duplicate/close events remain idempotent and cannot close or charge the other plane. |
| nftables policy | Rules are interface-scoped and have independently owned chains. The Family instance alone receives the narrow, audited post-auth service allow-list; Guest remains Internet-only. Neither instance may flush or replace the other instance's chains on restart. | Before/after-auth family-service tests plus Guest denial tests for NAS, PBX, camera/Tailscale, LuCI, and SSH; restart one instance and prove the other rules survive. |
| procd lifecycle | Guest and Family are separate procd services with explicit process identity, dependency/ordering, and rollback paths. | Kill/restart each service independently during an active client session; only that plane changes state and recovery does not widen access. |

The shared account/profile database is not an exception to these boundaries:
profiles are resolved by the same policy model, but native rate/time/volume
limits must be applied by the correct openNDS instance.

## Delivery order and rollback

1. Build a disposable-lab compatibility harness for the five isolation
   boundaries; it must not replace the target's stock init service.
2. Implement/test the adapter and plane-scoped schema/session contract.
3. Create one dedicated `br-family` network and SSID only after steps 1–2.
4. Enable the Family instance with a disposable family account; prove login,
   quota, and the service allow-list.
5. Prove the Guest instance still denies every family service.
6. Add Tailscale, independent-restart, and explicit rollback tests.

The first lab artifact is deliberately declarative:
`tools/family-captive-lab-validate.sh` validates unique bridge, runtime,
PID-file, log-file, control-socket, gateway-name, FAS-plane, nft-chain, and
procd-service identifiers. It is a guard against configuration collisions, not
evidence that two openNDS daemons are running.

Rollback is local and reversible: disable the Family SSID and Family daemon,
remove only its firewall/bridge/DHCP objects, and leave the existing
`br-hotspot` guest captive and `br-lan` services untouched. No broad
`authenticated_users` or `users_to_router` service allowance is part of this
decision.

## Consequences

- The desired single administration UI and account database are preserved.
- Family and guest authorization remain distinguishable at the enforcement
  boundary.
- This is a new compatibility workstream, not a quick UCI switch. It is
  **Implemented only as a readiness guard and architecture contract** until
  the required adapter and physical evidence exist.
