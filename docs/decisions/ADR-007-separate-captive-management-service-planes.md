# ADR-007: Separate captive, management, and router-service planes

**Status:** Proposed — pending operator approval and field design evidence  
**Date:** 2026-10-09  
**Requester:** OpenTik operator  
**Priority:** High

## Context and problem

The current target uses the router both as the captive gateway and as the host
for local services such as KSMBD and Asterisk. The existing topology document
describes `br-lan` as the captive-client plane, while the observed target also
has a distinct `br-guest` interface and the operator needs a separate
management/service path. The operator has clarified that `br-guest` is an
onboarding/transit network: a downstream router or device connects there as a
WAN/Internet client when its own LAN conflicts with the primary LAN. Treating
a portal page name as network isolation has blurred these roles and makes
symptoms look like openNDS faults when they may be a service listener, a
client-zone rule, or an upstream-device issue.

Changing only the portal FQDN or page title cannot create isolation: DNS names
do not separate firewall zones, interfaces, listeners, or routes. Likewise,
the already verified openNDS local-FAS contract must not be replaced by a
guessed hostname: `fasremoteip` remains unset and `gatewayfqdn` plus
`fasremotefqdn` remain `status.client` until a target-specific replacement is
proven.

## Decision

Adopt four explicitly separate network planes. The exact SSID names, VLAN IDs,
subnets, and physical ports are operator choices and are deliberately not
invented by the package.

```text
Internet / WAN
     │
     ├── Transit/onboarding plane: br-guest
     │     downstream-router WAN or temporary device Internet source
     │     DHCP/DNS + WAN egress only; no captive portal or service access
     │
     ├── Captive plane: dedicated SSID/VLAN/bridge
     │     openNDS gateway interface → local FAS → Internet after authorization
     │     portal display name: “OpenTik Guest Portal”
     │     protocol FQDN: status.client (until separately verified)
     │
     ├── Management + service plane: br-lan (or a named replacement)
     │     LuCI/SSH, KSMBD, Asterisk, local management clients
     │     never made captive merely to display the portal
     │
     └── IoT plane: dedicated SSID/VLAN/bridge
           IoT → WAN only; no forwarding to management/service plane
           no unverified trusted-MAC or preemptive-auth bypass

Tailscale
     └── explicit management/service access policy; no implicit guest transit
```

The portal is therefore a service on the router but not a claim that the
router's management address is a general-purpose captive client endpoint.
openNDS manages only the selected captive interface. Router-hosted services
remain on the management/service plane and are reached only by explicitly
authorized staff/service networks or narrowly scoped rules.

## Consequences

| Area | Effect |
|---|---|
| Transit/onboarding | A downstream router receives DHCP/DNS and WAN egress without sharing the management subnet; it does not receive portal, NAS, PBX, LuCI, SSH, or `br-lan` access. |
| Guests | Portal and Internet access are contained to the captive plane; they do not inherit NAS, PBX, LuCI, or SSH access. |
| Staff services | NAS/PBX clients use the management/service SSID/VLAN; a service listener fault is diagnosable independently of the portal. |
| IoT | Internet-only egress is explicit; it does not rely on a captive login or a MAC bypass. |
| Tailscale | Access to service subnets is an explicit routing/firewall decision, not a side effect of WAN or captive settings. |
| Portal naming | Branding can show “OpenTik Guest Portal”; changing the FAS hostname is a separate openNDS compatibility gate. |

## Change request

### Assess

This is a high-impact network change because moving an SSID, VLAN, or bridge
can disconnect clients. It resolves the structural ambiguity but does not
repair a stopped KSMBD listener, an incorrect SIP client port, or an offline
camera. Those are independent service facts.

### Implementation plan

| Step | Acceptance criterion | Rollback point |
|---|---|---|
| 1. Inventory | Record current SSIDs, VLAN/bridge membership, DHCP ranges, firewall zones, openNDS interface, service listeners, and Tailscale advertised/accepted routes without credentials. | No mutation. |
| 2. Stabilize transit | Preserve `br-guest` for downstream-router WAN/onboarding. After an alternate management path is proven, place it in an explicit transit firewall zone with DHCP/DNS to the router and forwarding to WAN only; no forwarding to `br-lan`. | Remove the transit zone/forwarding and restore the recorded firewall configuration from the management path. |
| 3. Choose the remaining planes | Operator selects one captive SSID/VLAN, one management/service SSID/VLAN, and one IoT SSID/VLAN or port. They use non-overlapping networks. | No mutation. |
| 4. Create captive plane | New bridge, DHCP, firewall zone, and SSID exist; openNDS is moved only after a wired/alternate management path is verified. | Disable the new SSID/zone and restore the recorded openNDS gateway interface. |
| 5. Prove portal | A disposable client sees `Preauthenticated`, reaches `status.client`, completes FAS login, and receives Internet; no service-plane access is implied. | Restore the prior openNDS UCI configuration and reload only after the management path is confirmed. |
| 6. Create IoT plane | IoT receives DHCP and reaches WAN only; it cannot reach management/service addresses. | Remove the IoT forwarding and restore its SSID/port to the prior zone. |
| 7. Add service access deliberately | Only the selected staff/service network receives required NAS/PBX ports after each service is locally listening. | Delete the specific allow rule; never use a broad guest-to-router allow. |
| 8. Tailscale proof | A tailnet client reaches only declared management/service destinations; captive and IoT planes remain unreachable unless explicitly approved. | Remove the declared route/firewall allowance. |

### Validation matrix

| Source | Destination | Expected result |
|---|---|---|
| Captive client before login | Portal (`status.client`) | Reachable; Internet blocked. |
| Captive client after login | WAN Internet | Reachable. |
| Captive client | LuCI/SSH/NAS/PBX | Denied unless an explicitly approved service rule exists. |
| Transit client | WAN Internet | Reachable through NAT. |
| Transit client | Management/service plane | Denied. |
| Management/service client | NAS/PBX on router | Reachable only after each daemon is locally listening. |
| IoT client | WAN Internet | Reachable. |
| IoT client | Management/service plane | Denied. |
| Tailscale client | Approved service destination | Reachable; all other paths denied by default. |

## Risk controls

- Preserve an independent wired or Tailscale management path before moving the
  openNDS gateway interface.
- Export the Open-HotSpot manager state and back up only the relevant UCI
  network, wireless, firewall, openNDS, and service configuration before the
  first mutation. Do not commit backups or credentials.
- Make one plane live at a time and test with one disposable client.
- Do not claim a portal hostname other than `status.client` works until its
  DNS, redirect, FAS, and device captive-detection behavior are field proven.
- Do not configure NAS/PBX exceptions until their local listeners are healthy.

## Approval required

Before implementation, the operator must supply the selected captive and IoT
SSID/VLAN or port and approve a maintenance window. `br-guest` must first have
an alternate management path available before its firewall is tightened. The
first implementation is `Pending Hardware Validation`; it does not change the
existing r101 portal contract or close any release gate by itself.
