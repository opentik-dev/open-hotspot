# Factory-router installation and integration runbook

This runbook is the repeatable path from a reset OpenWrt router to a release
acceptance decision. It is address-independent: discover the current LAN
address and never copy `192.168.1.1`, `192.168.2.1`, or an upstream address into
FAS configuration or source code.

## 0. Read the contracts first

Review [`official-contract-sources.md`](official-contract-sources.md), then
capture the target's exact `opennds -v`, OpenWrt release, target architecture,
UCI layout, stock `binauth_log.sh`, `custombinauth.sh`, and uhttpd config. If
the target differs from the official page, stop and add a row to the gap
register before implementing a compatibility change.

## 1. Factory-router preflight

Set a root password before delivery. Confirm the laptop has one route to the
router and that the upstream network and the router LAN do not share a subnet.
Discover the management address from the current DHCP/SSH session. Then run:

```sh
/usr/lib/open-hotspot/preflight.sh
```

The preflight must pass PHP/PDO-SQLite/hash, SQLite, uhttpd, UCI, openNDS,
topology, and readiness checks. It does not replace dnsmasq or edit an
existing FAS.

## 2. Install the base package

Install the architecture-neutral APK built for the target OpenWrt feed:

```sh
apk add --allow-untrusted /tmp/luci-app-open-hotspot-<version>-r<release>.apk
/usr/lib/open-hotspot/setup.sh base
/usr/lib/open-hotspot/setup.sh status
```

The base stage initializes SQLite and records a retryable state. It must not
silently replace dnsmasq, overwrite an external FAS, or create credentials.

## 3. Activate local FAS deliberately

After the base stage passes, activate the local FAS:

```sh
/usr/lib/open-hotspot/activate-local-fas.sh enable
```

The resulting contract is:

```text
gatewayinterface = discovered UCI LAN interface
fasremoteip      = unset
fasremotefqdn    = status.client
gatewayfqdn      = status.client
fasport          = 2080
faspath          = /nds/fas.php
fas_secure_enabled = 1
login_option_enabled = 0
custombinauth    = /usr/lib/opennds/custombinauth.sh
```

The stock `binauth_log.sh` remains the dispatcher. The manager adapter is
loaded through `custombinauth`; replacing the whole `binauth` option is not an
equivalent change because it can remove openNDS logging and `auth_restore`.

## 4. Run the integration diagnostic

```sh
/usr/lib/open-hotspot/diagnose.sh
```

Do not continue to client acceptance when it reports `FAIL`. A `WARN
integration=opennds-authenticated-without-manager-session` means the exact
gap that previously left LuCI empty: openNDS has a live client but SQLite has
not created the manager device/session.

## 5. Verify the service chain

The chain to prove is:

```text
DHCP/CPD probe
  -> openNDS redirect (port 2050 return server)
  -> local uhttpd FAS (port 2080 /nds/fas.php)
  -> FAS credential verification
  -> /opennds_auth handoff with opaque custom key
  -> stock binauth_log.sh
  -> custombinauth.sh / SQLite transaction consume
  -> openNDS authenticated client
  -> LuCI Devices/Dashboard and usage history
```

A successful openNDS status page alone is not enough. Acceptance requires the
SQLite transaction to become `consumed`, one device and one active session to
appear, then a close/deauth callback to create the expected usage event.

## 6. Phone/IoT acceptance procedure

For the phone test, disable WARP/VPN and mobile data, forget/rejoin the SSID,
open an HTTP URL, submit the existing acceptance account, and follow any
explicit `Continue` handoff. In parallel refresh LuCI Dashboard and Devices.
Record the portal, authenticated state, internet result, database counts, and
the diagnostic output. Repeat once with the VPN before login and once after
login to document the intended behavior.

IoT devices that cannot show a portal must be placed on a dedicated client/IoT
network with an explicit policy. Do not add an undocumented MAC bypass. Router
administration access is tested separately from portal access.

## 7. Restart/reboot acceptance

Test openNDS restart and full router reboot separately. For each test record:

1. openNDS state and manager active-session counts before the event.
2. openNDS readiness after the event.
3. whether the restore toggle is enabled or disabled.
4. client state, SQLite session, and usage-event counts afterward.

Do not call a reboot test successful merely because the phone has Internet;
that can be a stale openNDS state, VPN path, or an untracked session.

## 8. Evidence and release rule

Attach the diagnostic output, sanitized service/config summary, screenshots,
and exact package SHA-256 to `docs/field-evidence-YYYYMMDD.md`. Update the
matching row in [`integration-gap-register.md`](integration-gap-register.md),
`release-acceptance-matrix.md`, and `release-gates.md` in the same change.

The physical gate remains open until the fresh phone flow proves the entire
chain. Automated tests and isolated callback tests prove the implementation;
they do not replace the real-router client evidence.
