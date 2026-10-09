# Network service access diagnosis and safe policy

This runbook distinguishes three boundaries that must never be solved with one
blanket firewall exception:

1. **Captive clients** on the openNDS gateway: account-based authorization.
2. **Trusted IoT**: devices that cannot present a portal and need Internet
   egress, but must not gain router or management-LAN access.
3. **Administration and overlay access**: router administration, Tailscale,
   NAS, and PBX services.

## Accounts on more than one device

An account is not a MAC address. Its profile's `max_devices` is the maximum
number of simultaneous authenticated sessions. Set it to the required number
before logging in on another device. A second device then creates another
session under the same account without interrupting the first. A device MAC
already owned by a different account is deliberately rejected; use the audited
**Devices → Reassign** operation only after its live session is closed. Do not
make reassignment automatic.

## IoT Internet access

Do not place bulbs, plugs, cameras, or TVs that cannot complete a portal on
the captive `br-lan`. Put them on a dedicated non-captive IoT SSID, VLAN, or
wired bridge. Applying the Open-HotSpot isolation policy now creates exactly
one forwarding path: **IoT zone → discovered WAN zone**. It creates no path to
the management/LAN zone and continues to block router administration ports.

This deliberately is not a MAC allow-list. The exact openNDS 11 trusted or
preemptive-client contract is not an accepted project contract, so enabling it
would create an untested and unaudited bypass.

Before applying the policy, keep an administrator on a separate management
path and confirm the dedicated UCI network exists. Afterwards run:

```sh
/usr/lib/open-hotspot/router-access.sh status
/usr/lib/open-hotspot/network-audit.sh summary
```

Expected output includes `iot_wan_forward_src=open_hotspot_clients` and a
non-empty `iot_wan_forward_dest`. Confirm from an IoT device that Internet
works while router SSH/LuCI and the management LAN remain unreachable.

## Modem, Tailscale, NAS, and Asterisk diagnosis

Run the following commands on the router before changing firewall rules. Use
the actual service address only as a command argument; do not commit it in
evidence.

```sh
/usr/lib/open-hotspot/network-audit.sh summary
/usr/lib/open-hotspot/network-audit.sh route <upstream-modem-ip>
/usr/lib/open-hotspot/network-audit.sh route <nas-or-pbx-ip>
```

Interpretation:

- `route_device=wan*` for an upstream modem/service means routing is plausible;
  a remaining failure is likely the upstream device ACL, NAT source policy, or
  an explicit firewall rule—not a reason to widen openNDS.
- `route_device=br-lan` or an unexpected device indicates wrong subnetting,
  a missing static route, or LAN/WAN overlap. Fix topology first.
- `tailscale_interface=absent` means the overlay is not active on this router.
  If present but remote access still fails, inspect the Tailscale firewall zone
  and advertised/accepted subnet routes separately. Do not place `tailscale0`
  in the captive client zone.
- For NAS, test SMB from an **authenticated client** using the site's selected
  SMB port(s). For Asterisk, test the configured SIP port and configured RTP
  range; these values are deployment-specific and must not be guessed.

Only after this evidence should a narrow service rule be proposed. It must name
one source zone, one destination zone, protocol, and port/range; it must never
be a broad `br-lan → any` exception or a pre-auth openNDS allowance.

## Evidence required

For each failed and corrected path, record the sanitized audit output, the
source/destination zones, test client authorization state, and rollback rule
in the operational ledger. A successful router-side route lookup alone does
not prove SMB, SIP/RTP, Tailscale, or upstream-modem authorization.
