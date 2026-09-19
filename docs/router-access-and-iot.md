# Router access, IoT LAN, and VPN/captive-portal acceptance

This document records the two field findings that affected the final
acceptance attempt and the supported remediation shipped in r52.

## Why WARP appeared to bypass the portal

The phone test did not prove that WARP was accepted by the router. The target
log showed an openNDS startup/crash loop while the phone was joining the
managed network; openNDS became stable only later. During that window the
captive enforcement chain was not reliable. WARP also encrypts its tunnel, so
the router cannot identify the final websites inside it. If a tunnel was
already established, or the phone kept tunnel state across a Wi-Fi reconnect,
the phone could retain Internet access without a new HTTP portal request.

The later observation is consistent with this diagnosis: enabling WARP after
the captive path was active did not give the phone Internet access. The r52
package keeps the r51 readiness recovery, which requires openNDS to be ready
when local FAS is enabled and records a service failure when recovery cannot
complete. It deliberately does not add a WARP/VPN walled garden before login;
that would create an intentional route around captive authentication.

### Repeatable VPN test

1. Force-stop WARP and disable any other VPN/private-DNS tunnel.
2. Forget the Open-HotSpot SSID or disable/re-enable Wi-Fi to clear the old
   client path.
3. Join the managed SSID and confirm `ndsctl` reports the client as
   `Preauthenticated`.
4. Open `http://status.client`, submit the test account, and verify
   `Authenticated` plus Internet access.
5. Enable WARP and repeat an Internet request. If Internet stops, record it as
   expected policy behavior unless the product owner explicitly chooses to
   permit a post-auth VPN endpoint.
6. Repeat after an openNDS restart and after a router reboot. A client must not
   receive unrestricted Internet while openNDS is down.

## Router admin access option

openNDS preserves essential router ports, including SSH and HTTPS, for router
administration. Therefore `users_to_router` alone is not a complete deny rule.
See the [official openNDS configuration reference](https://github.com/openNDS/openNDS/blob/master/linux_openwrt/opennds/files/etc/config/opennds).

r52 adds `router-access.sh` and a LuCI Setup option:

- `Managed client network`: the UCI network name attached to the client/IoT
  SSID, VLAN, or LAN port.
- `Router admin access = Deny`: drops client TCP access to ports 22, 80, and
  443 on the router, independently of the router's current IP address. Captive
  portal ports 2050 and 2080 remain available.
- `Router admin access = Allow`: removes the package deny rule.

The operation refuses a network using the same device as the openNDS
gateway/management interface. This is intentional: applying a deny rule to the
shared `br-lan` would also lock out the administrator and is not a valid IoT
isolation design. On the current test topology, create the dedicated network
and SSID first; do not apply the policy to the existing shared `br-lan`.

## IoT network design

Create a separate OpenWrt network with a distinct logical device/bridge, then
attach one or more of the following to that network:

- an IoT Wi-Fi SSID;
- a VLAN-backed LAN port;
- an isolated bridge containing the chosen wired devices.

Use the network's UCI name in LuCI, save, then apply the policy. The package
does not invent an address, VLAN ID, SSID, or bridge; it consumes the live UCI
network definition and therefore remains valid when the router LAN address
changes. A multi-network deployment must attach the client network to the
openNDS-managed client path or provide a separately configured openNDS
instance; simply creating a second firewall zone does not make it captive.

## Rollback

Set `Router admin access` to `Allow` and apply. If the dedicated network is no
longer present, remove the package rule from the router's firewall configuration
from the admin plane, then reload the firewall. Never perform the deny test on
the only management path.

## Clean-router guide adaptation — apk/dnsmasq-full

The field guide is useful on this target, but its commands must be adapted to
OpenWrt 25.12.5: the router uses `apk`, not `opkg`. `dnsmasq-full` is available
from the target feed and provides `nftset`; replacing the base `dnsmasq` kept
the DHCP configuration and the Open-HotSpot/openNDS UCI configuration byte-for-
byte identical. It is therefore a valid prerequisite for features that use
dnsmasq nftsets, but it is not a substitute for preserving the project FAS
options.

Do not apply the guide's minimal `/etc/config/opennds` here. It would remove
the generated local FAS key, `fasport`, `faspath`, `fas_secure_enabled`,
`gatewayfqdn`, and the local `users_to_router` allowance. A clean install must
back up and merge the existing project configuration instead of overwriting it.

On the acceptance router, installing `dnsmasq-full` produced the expected
`nftset` compile flag and left DHCP healthy, but openNDS still reached
`openNDS is now running` and then exited after reporting a dnsmasq reload
failure. procd subsequently reported `exit_code=139`. This means the package
swap closes the dnsmasq capability gap but does not close the current
openNDS/OpenWrt runtime gate; the router is not a production baseline until
that gate is independently fixed and retested.
