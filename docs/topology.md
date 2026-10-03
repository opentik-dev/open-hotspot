# Open-HotSpot topology contract

## Supported arrangement

The upstream Internet path may change independently of Open-HotSpot:

```text
Upstream router / Wi-Fi Internet
              │  DHCP/WAN/relay path; address may change
              ▼
      Open-HotSpot router
        ├── br-lan: captive clients and local FAS
        └── admin Ethernet: LuCI/SSH management
```

The client under test must join the Open-HotSpot router's managed `br-lan`
SSID or LAN. A laptop that keeps its default route on the upstream Wi-Fi while
using Ethernet only to reach LuCI is an administrator connection, not a
captive-client test. That laptop will bypass openNDS for its Internet traffic.

For the common two-router arrangement, keep the primary router on its current
upstream LAN, give the Open-HotSpot router a WAN/uplink lease from the primary,
and give its `br-lan` a different, non-overlapping LAN subnet. The admin
laptop's Ethernet address belongs to the Open-HotSpot LAN with no default route
or DNS on that interface, while its Wi-Fi remains the Internet default route
through the primary. If the secondary has only a laptop Ethernet cable and
no WAN Ethernet or Wi-Fi-STA/relay uplink to the primary, it cannot provide
Internet access; management connectivity is not an upstream connection.

The package preflight rejects a duplicate local address, an Open-HotSpot LAN
address equal to the default gateway, and an identical LAN/WAN route. These
checks are diagnostics and do not automatically rewrite router networking.

## FAS address rule

Local activation must leave `fasremoteip` unset and set both
`fasremotefqdn` and `gatewayfqdn` to `status.client`. openNDS 11 otherwise
renders `Remote Portal Not Defined` when `login_option_enabled=0`, even when a
local listener exists. The FAS listener remains on the local router at port
`2080`. `status.client` is resolved by the router's captive-DNS state, so no
LAN/WAN address is stored in the FAS contract.

This does not make the local router address irrelevant to packet delivery: a
client still needs a route to the Open-HotSpot gateway. It removes the fragile
dependency on the upstream router's address or WAN lease. If the Open-HotSpot
LAN address itself changes, openNDS must be restarted/reloaded after the
network change so its generated local DNS/redirect state is refreshed.

## Acceptance checks

- [ ] Change the upstream router/Wi-Fi source without editing openNDS FAS UCI.
- [ ] Confirm `fasremoteip` is empty and both FAS/gateway hostnames are
      `status.client`.
- [ ] Confirm `gatewayfqdn=status.client`.
- [ ] Confirm `http://status.client` resolves for a client connected to
      Open-HotSpot `br-lan`.
- [ ] Confirm an administrator connected only by Ethernet can reach LuCI while
      the client test is performed on the Open-HotSpot SSID.
- [ ] Record the current gateway address from `ndsctl status` as runtime
      evidence, not as a configuration constant.
