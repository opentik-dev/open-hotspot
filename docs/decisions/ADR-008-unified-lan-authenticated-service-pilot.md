# ADR-008: Controlled unified-LAN authenticated-service pilot

**Status:** Proposed — target contract verified; physical security proof pending
**Date:** 2026-10-09
**Supersedes:** the absolute shared-LAN conclusion in ADR-007 and the
corresponding wording in the network remediation plan. ADR-007 remains the
production-safe default.

## Decision

Open-HotSpot may support a **controlled pilot** in which openNDS runs on the
same LAN bridge as router-hosted services, but only after the exact target
proves that `authenticated_users` grants the intended router-service access
*after* authentication and does not broaden pre-authenticated access.

This is a single **portal and policy plane**, not a claim that all identities
have the same permissions. The portal, accounts, quotas, duration, and rate
profiles remain one Open-HotSpot experience. The network implementation still
must distinguish the following:

| Identity / flow | Required handling |
|---|---|
| Unauthenticated client | Portal, DHCP, and DNS only; no NAS, PBX, camera, LuCI, SSH, or Internet. |
| Authenticated family client | Internet plus only the explicitly tested NAS/PBX/camera services. |
| Authenticated guest | Internet. Native openNDS `authenticated_users` rules are global, so it cannot be promised a different router-service entitlement merely because it has a different portal account. |
| IoT device | Separate IoT plane is the production default. A preemptive-client pilot is separate, and must prove manager accounting before it can replace that plane. |
| Tailnet client | Explicit `tailscale0` firewall/routing policy; it is never an incidental consequence of captive rules. |

Consequently, a one-bridge solution is acceptable only when every authenticated
user is trusted to reach the selected services and those services enforce their
own credentials. If a guest must be denied NAS/PBX while a family member is
allowed, retain separate data planes/VLANs while presenting the same portal and
Open-HotSpot administration interface.

## Verified target documentation contract

The exact openNDS 11.0.0 package installed on the target documents:

- `authenticated_users` rules are ordered; if no rule exists, authenticated
  clients have unrestricted access. An allow rule is still subject to the
  OpenWrt firewall.
- An authenticated rule can select protocol, port, and destination.
- `users_to_router` is a distinct router-access ruleset and must not be used
  to expose NAS/PBX before login.
- `preemptivemac` clients retain usage monitoring, quotas, timeouts, and FAS
  logging, unlike `trustedmac` clients.

The official upstream configuration and change history additionally state that
authenticated users can be granted router access through
`authenticated_users`. This corrects the previous claim that router-hosted
services must always be moved behind another host to obtain a post-login rule.

This is a **documentation/contract verification**, not field proof of the
installed nftables realization. The live pilot below remains mandatory.

## Non-negotiable pilot gates

1. The working dedicated `br-hotspot` deployment remains untouched as rollback
   until every test below passes.
2. Before any shared-LAN mutation, create and verify an on-device archive of
   `network`, `wireless`, `firewall`, `opennds`, and Open-HotSpot UCI state.
   Never add that archive to Git.
3. Use one disposable client and a second independent management path.
4. Do not enable `users_to_router_passthrough`; do not add broad `allow all`
   rules to `users_to_router`; do not use `trustedmac`.
5. Do not encode service ports from assumptions. Derive the final rule list
   from the target listeners and application configuration on the day of the
   test.
6. Do not enable a shared-LAN profile in the packaged guard until the exact
   before/after-auth contract is field-proven and captured in the ledger.

## Field experiment — one changed variable at a time

| Step | Mutation | Acceptance evidence | Immediate rollback trigger |
|---|---|---|---|
| U0 | None: record baseline with dedicated plane live. | Management NAS/PBX/camera/Tailscale checks and guest portal login are recorded separately. | Any existing regression. |
| U1 | Move only the gateway interface to the candidate bridge; retain the existing restrictive router rule list. | Disposable client is `Preauthenticated`; FAS works; SMB/SIP/router admin are denied. | Management path is lost or a service is reachable pre-login. |
| U2 | Add exactly one `authenticated_users` candidate rule for one harmless, verified service listener. | The service remains denied pre-login and becomes reachable after login; Internet remains usable; LuCI/SSH stay denied. | Rule changes pre-login reachability, breaks Internet, or exposes management. |
| U3 | Repeat one service at a time for SMB, SIP signalling, RTP media, and camera management/streaming only when their actual ports are independently known. | Each protocol passes after login and is denied before login. | Any unexpected port/path. |
| U4 | Test a tailnet-originated camera/service flow and return path. | Approved service works; portal/IoT paths are still denied. | Tailscale is degraded or crosses into captive/IoT unintentionally. |
| U5 | Test a guest account separately. | If it gains the same service access, record the native global-rule limitation and keep segmented guest access. | Any claim of account-specific isolation without enforcement proof. |

The pilot is accepted only if U0–U5 have physical evidence. It does not close
quota, counter, reboot, or manager-accounting gates.

## Rollback

Stop openNDS, restore the saved UCI configuration, reload network/firewall and
the previous openNDS configuration through the known recovery path, then verify
the dedicated portal and management service path separately. A failed pilot is
evidence, not a reason to add broader exceptions.

## Consequences

- The r102 `protected`/`isolated` service-plane guard stays the package default.
- A future `authenticated-shared-service` guard mode requires a new ADR update,
  an automated contract test, and the U1–U5 physical evidence above.
- The user-facing product may still be one portal and one administration UI
  while family, guests, transit, IoT, and Tailnet use their appropriate
  enforcement planes under the hood.
