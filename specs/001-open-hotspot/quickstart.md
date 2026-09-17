# Quickstart — Manual Validation Walkthrough (v1.2)

## Phase 0 target evidence

The first target is `192.168.70.1` (Linksys EA8300, OpenWrt 25.12.5,
`ipq40xx/generic`, openNDS 10.3.1-r3). The read-only inspection commands used
were:

```sh
ssh root@192.168.70.1 'ubus call system board'
ssh root@192.168.70.1 'opennds -v; ndsctl; uci show opennds'
ssh root@192.168.70.1 'sed -n "1,220p" /usr/lib/opennds/binauth_log.sh'
ssh root@192.168.70.1 'sed -n "1,260p" /usr/lib/opennds/authmon.sh'
```

Observed target v10.3.1 contract: `auth_client` receives method, MAC,
origin URL, user agent, client IP, token, and custom value. Other callback
reasons receive method, MAC, incoming/outgoing byte counters, session
start/end, token, and custom value. The default script returns five numeric
policy values and uses exit status 0/1 for allow/deny. FAS level 1
returns the documented HID flow; FAS level 4 returns `rhid`, session length in
minutes, rates in kbit/s, quotas in kBytes, and a custom BinAuth value.

The router initially had no WAN route, which made the old external FAS probe
fail with status 4. After the reversible cleanup and local-FAS activation on
2026-09-17, openNDS reported upstream `192.168.50.1` online and the local FAS
listener was reachable from the LAN.

Local-only implementation baseline: use FAS level 1 on a separate uhttpd HTTP
port, planned as `2080`, with `.php=/usr/bin/php-cgi`; port 80 remains reserved
for the openNDS captive portal. The bundled endpoint is `/nds/fas.php` and
returns the documented HID/token handoff with an opaque `custom` transaction
key. This baseline is derived from the official FAS guide. It is now active on
the test router only after an explicit second-stage activation; the base
package still does not change openNDS configuration implicitly.

Startup timing observed after a router reboot: the first openNDS attempt failed
because `br-lan` was not ready; the second attempt took about 15 seconds from
startup to `openNDS is now running`. The service became usable after the router
recovery window at roughly 80–100 seconds in the SSH polling test. A service
restart command returns in about 1 second, but readiness took about 30 seconds
after the old process exited because procd respawned the daemon.

The Phase 1 foundation was also checked on the target: SQLite initialization
created an idempotent v1 database and rejected an unversioned database, while
the period helper produced valid UTC boundaries on the router's ash/BusyBox
environment.

## Completed installation checkpoint — 2026-09-17

The old application state was archived, not destroyed, at:

```text
/etc/open-hotspot/legacy-20260917T005422Z
/usr/lib/open-hotspot-legacy-20260917T005422Z
```

The sysupgrade and state backups are stored locally under
`.build/backups/20260917T003034Z.*`. The installed package is
`luci-app-open-hotspot 1.2.0-r16`, built for `noarch` as an OpenWrt APK:

```text
sha256 04778451a1fb5a9a293ca8ed80a617bdde7bfa6b68a31c54889999902740d643
```

The router now reports `BASE_READY`, local FAS level 1 on port `2080`, and
`local_fas_enabled=1`. `openNDS` reports FAS URL
`http://192.168.70.1:2080/nds/fas.php`, and uhttpd listens on port 2080.
The gateway client-status hostname is set to `status.client`; dnsmasq resolves
it to `192.168.70.1` for captive clients.
The WAN lease is `192.168.50.156/24` with gateway/DNS `192.168.50.1`; the
reported `udhcpc: no lease` occurred during a service restart and did not
replace the active lease. `dnsmasq-full` is installed and provides the required
nftset build option.
The FAS login was tested with a temporary account using a real HTTP POST; the
response contained the `tok`, `custom`, and `redir` handoff fields and created
one pending SQLite transaction. The account was then suspended and the test
transaction expired; database integrity remained `ok`.

For the current Wi-Fi trial, all three radio interfaces are enabled with the
open SSID `Open-HotSpot-Test` on the LAN bridge. The first active account is
`firstuser` on `default-unlimited`; its credentials are intentionally not
stored in repository documentation.

Submitting those handoff fields from the management host to `/nds/` returned
HTTP 511 and did not create an openNDS client, which is expected because the
host was not a separate captive client on the managed path. Therefore the
portal-to-BinAuth/session-close gate is intentionally still open.

To inspect or reverse the explicit activation:

```sh
ssh root@192.168.70.1 '/usr/lib/open-hotspot/activate-local-fas.sh status'
ssh root@192.168.70.1 '/usr/lib/open-hotspot/activate-local-fas.sh rollback'
```

## SDK/feed build procedure

The official SDK is a package-focused buildroot, not a complete firmware
build. Add the project as a local feed, update feeds, install the package, and
disable “Select all target specific packages by default” in Global Build
Settings before selecting the application. The relevant official references
are the [OpenWrt SDK package-feed guide](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk#package_feeds),
the [OpenWrt feeds guide](https://openwrt.org/docs/guide-developer/feeds), and
the [single-package build guide](https://openwrt.org/docs/guide-developer/toolchain/single.package).

For this APK-based 25.12 SDK, the final package was assembled with the SDK's
own `staging_dir/host/bin/apk mkpkg` after staging the local feed payload. This
avoids rebuilding PHP, Lua, and unrelated target defaults; runtime dependency
availability is checked on the target during preflight. A normal SDK
`make package/luci-app-open-hotspot/compile V=s` remains valid when the host
has working fakeroot and all selected feed dependencies; in this environment
the generic invocation additionally tried to rebuild the toolchain and was
blocked by the sandbox's fakeroot restriction.

1. Flash/boot a stock OpenWrt 25.12.x device; install
   `luci-app-open-hotspot`. Confirm the verified core dependency plan completes
   without a lost DNS/DHCP window; `dnsmasq-full` must not be swapped in by the
   package.
2. **LuCI → Services → Open-HotSpot → Setup**: confirm the state reaches
   `BASE_READY`, the planned FAS is `local-level1` on port `2080`, and
   `local_fas_enabled` is `0` before the deliberate activation step. A
   preflight or database blocker must be visible as a recorded state, not a
   silent partial install.
3. After the base acceptance gate is closed, run
   `activate-local-fas.sh enable` and validate portal → FAS → BinAuth on a
   disposable client. The installed router has completed the FAS portion; the
   remaining closure requires a separate Wi-Fi/LAN client session through the
   captive portal.
4. **Profiles**: create "daily-light" — daily, time_limit=2h,
   download_limit=500MB, max_devices=2.
5. **Accounts**: create "ahmed" (set a PIN), profile=daily-light.
6. Connect test device A, log in on the portal as "ahmed" with the PIN
   (not by MAC). Confirm a row appears in `devices` for A, linked to
   ahmed's account (SC-007 setup).
7. Connect test device B, log in as "ahmed" again. Confirm B is
   registered as ahmed's second device.
8. Attempt a third device C. Confirm it is refused (max_devices=2)
   until A or B is removed/blocked (**SC-007**).
9. Consume time/data past the daily-light limit (or temporarily lower
   limits for the test), combined across A+B. Confirm both devices are
   disconnected automatically at whichever limit is hit first, and the
   portal reflects "quota exceeded" on the next attempt.
10. **Status**: confirm the dashboard shows ahmed's consumed vs. remaining
   time/data and device count correctly before and after cutoff.
11. From **Accounts**, click **Renew** on ahmed; confirm A/B can
    reconnect immediately with a fresh period.
12. Reboot the router mid-session for a second connected test account;
    confirm on reboot that already-accrued usage for the current period
    is unchanged (not reset, not doubled) (**SC-002**).
13. Kill the `open-hotspot` init script only (not `opennds`); confirm
    already-authenticated devices keep Internet access uninterrupted
    (**FR-011 / SC-004 / SC-005**).
14. Set a 2-minute test period on a profile; let it roll over while a
    device is connected; confirm `cycle.sh` closes/opens the period and
    reissues an updated ceiling to the live device without a hard
    disconnect (**FR-006**).
15. **Vouchers**: generate a batch of 2 codes on "daily-light". Redeem one
    code from a fresh browser session; confirm it creates a new account
    and flips the voucher to `redeemed`. From two separate sessions,
    attempt to redeem the *same* code simultaneously; confirm exactly one
    succeeds and the other is rejected (**SC-008**).
16. Trigger two rapid deauth events for the same device in immediate
    succession (e.g. `ndsctl deauth` called twice back to back); confirm
    `usage_periods` reflects the session once, not twice (**SC-006**).
