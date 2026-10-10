# Field evidence log — EA8300 A/B acceptance

**Date:** 2026-09-18  
**Artifact under test:** `luci-app-open-hotspot 1.2.0-r60`
**Target:** Linksys EA8300, OpenWrt 25.12.5 r33051-f5dae5ece4, `ipq40xx/generic`  
**Status:** r60 installed and target-validated with local FAS enabled; reboot restore is proven in both modes, while restart accounting remains open.

The follow-up r47 source/build change was completed locally after this field
attempt. It adds a dynamic local-FAS configuration guard, topology separation
preflight, and the executable mode required for direct preflight invocation.

## r51 build and target evidence

- APK: `dist/luci-app-open-hotspot-1.2.0-r51.apk`
- SHA-256: `f97200da0d23bbc04625972e8c6473904eb7ce6d69d41bb2cfe65ba01de35652`
- The checksum matches `dist/SHA256SUMS`.
- Python unit tests, shell syntax, quota, and all `tests/test_*.sh` contract
  tests passed after the topology guard was added.
- Target board: Linksys EA8300, OpenWrt 25.12.5, boot partition 1.
- Target topology: `br-lan` and WAN were discovered from the live interfaces;
  they were non-overlapping and preflight reported `topology=ok`.
- Target installation completed with `apk add`; setup reached `BASE_READY`,
  schema version `4`, RPC registration, and PHP syntax validation succeeded.
- `ndsctl status` reported openNDS 10.3.1 with managed interface `br-lan`,
  `Gateway FQDN: status.client`, secure FAS on port `2080`, and online WAN.
- The repeated activation test left exactly one `users_to_router` allowance;
  `fasremoteip` and `fasremotefqdn` remained unset.

## Successful checks

1. The installed Advanced Reboot RPC identified the board as `linksys,ea8300`.
2. `obtain_device_info` reported:
   - partition 1: `mtd10`, OpenWrt 25.12.5, Linux 6.12.94;
   - partition 2: `mtd12`, OpenWrt 25.12.5, Linux 6.12.94;
   - active partition: `2`.
3. `fw_printenv` confirmed `boot_part=2` before the test.
4. The manager backup from slot 02 validated successfully and was copied to:
   `.build/backups/20260918T000000Z.open-hotspot-ab-before-switch.tar.gz`.
5. Backup SHA-256, verified both remotely and locally:
   `21600c30b52ebe04fdc0425f9d6755f673cc37c38478a396ecb3de2ac49e6432`.
6. The official Advanced Reboot RPC accepted partition 1 and reported
   `rpc_rc=0`, `boot_part=1`.
7. After reboot, the management network moved from `192.168.70.1` to
   `192.168.1.1`, as expected for the alternate boot's network state.
8. HTTP on `192.168.1.1` served the OpenWrt LuCI redirect page.

## Errors and blocked steps

### E-001 — SCP/SFTP transport unavailable

`scp` failed with:

```text
ash: /usr/libexec/sftp-server: not found
scp: Connection closed
```

This was a transport limitation on the router, not an application failure.
The backup was transferred successfully with an SSH `cat` stream and the
local SHA-256 matched the remote SHA-256.

### E-002 — SSH unavailable on slot 01

At `192.168.1.1`, TCP/22 timed out while HTTP/80 returned LuCI. No SSH key
exchange or authentication occurred, so no key was changed or installed.

### E-003 — LuCI credentials unavailable

The unauthenticated LuCI page was reachable. A blank-password login attempt
for `root` was rejected with `Invalid username and/or password!`. No password
was guessed further and no factory reset was attempted.

### E-004 — Management and client paths were conflated

The admin machine received `192.168.1.191` from the alternate boot and could
reach LuCI over HTTP at `192.168.1.1`, while its previous route to
`192.168.70.1` disappeared. This confirms that the upstream/management address
can change independently. It also confirms that an administrator connected by
Ethernet is not evidence of a client traversing the Open-HotSpot `br-lan`.

## Current operational state

- The router is booted on slot 01; `boot_part=1` was confirmed remotely.
- Its current LAN and WAN addresses were discovered from live interfaces and
  are intentionally recorded as runtime evidence, not project constants.
- r51 is installed on slot 01. `setup.sh base` reached `BASE_READY`, the
  schema is version `4`, RPC methods are registered, and PHP syntax passed.
- Slot 02 remains the intended recovery slot and was not modified after the
  backup.

## Required continuation

Run the disposable-client, quota/counter, restart/restore, failure-containment,
management-isolation, backup/import, and A/B rollback checks from the runbook.
No live-client production gate is closed by the base installation alone.

## E-005 — Host Wi-Fi profile reverted during captive-client attempt

The target initially had all factory Wi-Fi interfaces disabled. For the
acceptance attempt, `radio1` was temporarily enabled with the open SSID
`Open-HotSpot-Test` on the managed `lan` network. The SSID became visible and
the host briefly associated and received a DHCP address from the Open-HotSpot
LAN. NetworkManager then automatically reconnected the host to its primary
Wi-Fi profile before the HTTP probe, so the probe ran from the upstream network
and was correctly not counted as captive-client evidence. A subsequent host
network-profile change required elevated desktop authorization and was not
performed after that authorization was denied. The SSID test configuration
remains a field-only router change; it is not an application address
dependency.

## E-006 — Phone captive-client test and startup-loop closure

The phone received a DHCP lease on the managed LAN (`192.168.2.200`) and the
first captive flow displayed the styled Arabic Open-HotSpot login page. The
phone did not submit credentials, so `Authenticated` was not observed. After
the connection dropped, it reconnected with Internet access without showing a
portal; this was recorded as a failure, not a success.

Target evidence showed openNDS in a procd crash loop while the LAN/firewall was
settling. The loop allowed traffic to bypass captive enforcement. The direct
foreground diagnostic showed openNDS itself could start once `br-lan` and WAN
were ready. r49 carries the init-time readiness check: when local FAS is
enabled, Open-HotSpot requires `ndsctl` readiness and records `SERVICE_FAILED`
if recovery cannot complete. After installing r51, `setup.sh base` reached
`BASE_READY`, `/etc/init.d/opennds status` was `running`, `ndsctl status` showed
secure local FAS on port 2080, and a CPD request through `/login` returned the
Arabic FAS document. No live login/accounting claim is made from this test.

The unstyled status screenshot is explained by the same timing window: the
captured page was generated while the service was unstable. Once stable, the
status page's CSS and splash image returned HTTP 200 through the dynamic
`status.client` path; no fixed router address was added to the project.

## E-008 — WARP/VPN observation and management-port proof

The phone test reported Internet access after reconnecting without a portal,
while Cloudflare WARP was running in the background. The router has no WARP
identity or decrypted tunnel visibility; the target also had no WireGuard
interface or connection-tracking utility available for attribution. The
proven router-side event was the openNDS crash loop recorded in E-006, during
the same join window. A persistent or pre-established encrypted tunnel is a
possible contributing factor, not a confirmed router-side allow rule. When
WARP was enabled after captive enforcement was restored, it did not provide
Internet access, which is consistent with the pre-auth firewall rejecting a
new tunnel.

The target firewall proof also showed that `users_to_router` containing only
the local FAS port does not deny router administration: openNDS's router chain
still accepts the essential SSH and HTTPS ports. r52 therefore adds a
port-based deny rule for a separate UCI client network. It is address-agnostic,
refuses the same gateway device, and was not applied to the current shared
`br-lan` because that would risk administrative lockout. A physical test on a
new isolated IoT SSID/VLAN remains required before closing that gate.

The repeatable VPN and IoT-network procedure is in
[`router-access-and-iot.md`](router-access-and-iot.md).

## E-007 — r50 post-install and managed-LAN enforcement

r51 was installed over r50 from the final APK. Its tracked post-install hook
ran the idempotent base setup and the router reported `state=BASE_READY` with
an empty `last_error`. Because local FAS was already enabled, the hook also
exercised the Open-HotSpot service readiness path; openNDS remained `running`
and `ndsctl status` continued to report secure local FAS on port 2080.

From the managed LAN, an unauthenticated HTTP client then received `511 Network
Authentication Required`; `/splash.css` and `/images/splash.jpg` returned
HTTP 200, and `/login` returned a 307 redirect to the local FAS endpoint. This
closes the previously observed service-down/unstyled-page failure for the
tested restart state. It does not close live credential authentication,
BinAuth, quota, or restart/session-restore gates. The explicit FAS activation
path also found a valid 64-character target-local key without exposing its
value.

## E-009 — r55 guard closure and target openNDS blocker

r55 was built, checksum-recorded, installed over r54, and its RPC method
`router_access_set` appeared after an rpcd restart. Applying `deny` to the
current shared `lan` network returned a nonzero result with
`client network must be isolated from the gateway/management interface`; no
Open-HotSpot firewall zone or deny rule remained. This closes the accidental
r54 fail-open guard defect.

The same target then failed the live service gate independently of the
package's router-access code. After a clean reboot and after temporary
runtime cleanup, procd reported `/usr/bin/opennds -f` with `exit_code=139`.
`ndsctl status` returned either `opennds probably not yet started` or `thread
is busy`, while openNDS repeatedly logged only its startup banner. Running
without the local FAS options produced the same result; the FAS key and
project configuration were restored afterward. This is an openNDS/OpenWrt
target-image blocker requiring a separate binary/core/configuration diagnosis,
not evidence that WARP is allowed through the project.

The r55 account `acceptance-r55` was created successfully with the default
profile. It must not be called a successful captive login until openNDS is
stable and the client reaches `Authenticated`.

## E-010 — Adapted clean-router guide and dnsmasq-full retest

The supplied clean-router guide was evaluated against the current Linksys
EA8300 image. The target uses `apk`; `opkg` is absent. The target feed provides
`dnsmasq-full-2.93-r1`, which replaces the base `dnsmasq` and adds the `nftset`
compile option. Before the replacement, `/etc/config/dhcp` and
`/etc/config/opennds` were backed up. After installation and dnsmasq restart,
both files had the same SHA-256 as their pre-change copies, `dnsmasq --test`
passed, and the dnsmasq service reported `running`.

The project openNDS configuration was deliberately not replaced by the guide's
minimal example because that would remove local FAS and project firewall
allowances. After firewall/openNDS restart, a direct foreground run reached
`openNDS is now running`, but openNDS then logged `Dnsmasq restart failed!` and
exited; procd returned to the observed `exit_code=139` startup loop and
`ndsctl status` remained unavailable. Therefore `dnsmasq-full` closes a real
capability gap for nftset-dependent features, but it does not close the target
openNDS runtime gate. The target remains a diagnostic environment, not a final
delivery baseline.

## E-011 — Official openNDS diagnosis and r58 startup fix

The official openNDS documentation confirms that the managed interface must be
an IPv4 LAN gateway providing DHCP, DNS, and NAT, and that preauthenticated
clients are blocked except for the documented portal/router allowances. The
target satisfied the topology requirements: `br-lan=192.168.2.1/24`, WAN
`192.168.50.190/24`, DHCP lease `192.168.2.200`, and an online upstream
gateway.

The documented debug procedure was applied at level 3. A direct foreground
openNDS process reached the CPD redirect to the local FAS, proving the binary,
FAS path, and client detection were functional. The failure occurred only when
the OpenWrt procd wrapper forwarded stdout with `procd_set_param stdout 1`:
procd repeatedly reported `exit_code=139`, removed the openNDS nftables chains,
and allowed the ordinary LAN forward path to pass traffic.

r58 applies the target-proven compatibility change during both post-install and
post-upgrade, saves the original init file, and removes only that exact stdout
directive for openNDS 10.3.1. After r58, the target reported `running`,
`ndsctl status` succeeded, the phone appeared as `Preauthenticated`, and the
`nds_filter/nds_nat` chains were present with preauth reject counters. The live
credential/FAS authentication and reboot-retention tests remain open; direct
Internet bypass from the crashed-service state is closed for the tested startup
path.

## E-012 — Live login and router reboot retention test

On 2026-09-19 the disposable phone client completed the local portal login with
the `acceptance-r55` test account. Before reboot, `ndsctl status` reported the
client as `Authenticated`, `Client authentications since start: 1`, and the
client had an active session window. This closes the basic live portal/FAS
credential observation for this account, but it does not by itself close the
manager-session, BinAuth accounting, or quota gates.

The router was then rebooted. After the network returned, openNDS was running
under procd, `ndsctl status` was available, the upstream gateway became online,
and the `nds_filter/nds_nat` chains were recreated with preauthentication reject
counters. The same phone was present as `Preauthenticated`, not
`Authenticated`, so Internet access was blocked until a new login. This is the
expected result for the current target BinAuth configuration: the default
authentication log script does not restore live openNDS sessions across a
router reboot. It is therefore a successful fail-closed reboot result, not
evidence of live-session persistence.

An early boot log also contained `Dnsmasq reload failed!` and a transient
upstream-offline message; openNDS later reported `openNDS is now running` and
the upstream gateway online without another process crash. The separate T011
gate remains open for openNDS-service restart, SQLite usage persistence, and a
formal decision on whether live-session restoration is required for delivery.
## E-013 — Configurable manager-owned session restore

r59/r60 add a LuCI Setup policy named `session_restore`, disabled by default.
The enabled path is deliberately manager-owned rather than a blind activation
of openNDS's volatile stock `auth_restore`: after openNDS is ready, the helper
selects active SQLite sessions, rechecks account status and current quota
remaining, and calls the verified native adapter outside BinAuth. The existing
SQLite session key is passed back as the openNDS custom context so later close
accounting remains idempotent. A per-process marker prevents repeated
reauthorization and permits a retry after startup ordering or openNDS PID
changes.

Target validation then exposed a real 10.3.1 behavior: `ndsctl auth` rejected
the client MAC directly but accepted the currently leased client IP. r60
resolves that IP from `ndsctl status` at runtime and never stores a router or
client address in the package. With the setting enabled through the LuCI RPC,
the router rebooted, the first restore attempt waited for openNDS readiness,
and the retry completed with `restore_attempted=1`; the phone was
`Authenticated` without a new portal submission. With the setting disabled
through the same RPC and a second reboot, `restore_attempted=0` and the phone
was `Preauthenticated`, so the portal was required again. BinAuth remains free
of `ndsctl` calls in both modes. The remaining T011 work is separate openNDS
restart accounting and persistent usage-deduplication evidence.
