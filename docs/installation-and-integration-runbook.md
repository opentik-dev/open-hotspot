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

## 2. Deploy candidate package via guarded deployment driver

For candidate deployment (such as `1.2.0-r92`), use the official guarded driver
only on the isolated r90/r91/openNDS 11.0.x candidate slot. The r60/openNDS
10.3.x baseline is a rollback target and must not be upgraded in place by this
driver:

```sh
# Verify local artifact integrity only:
tools/deploy-r92.sh --check-local

# Execute guarded deployment to router:
ROUTER_IP=192.168.50.1 tools/deploy-r92.sh
```

The driver executes with `set -euo pipefail` and `umask 077`, enforcing strict fail-closed barriers:
1. **Local verification**: Validates artifact existence, exact expected SHA-256 (`a93ab78f04315017c2c4e0fd1d5ac5595024634de8d9d31b5c86aafb0ad655db`), `apk --allow-untrusted verify`, and `apk adbdump`.
2. **Router identity inspection**: Interrogates router board model, active boot slot, and `opennds -v`; the expected EA8300/slot-2 identity is fail-closed by default. The probe captures the actual exit code, but accepts a non-zero code only when the output contains a parseable OpenNDS version; this covers the observed OpenNDS 11.0.0 behavior where `opennds -v` prints a valid version and exits 1.
3. **Read-only preflight & diagnostics**: Runs `/usr/lib/open-hotspot/preflight.sh` and `/usr/lib/open-hotspot/diagnose.sh` prior to mutation; aborts immediately on non-zero exit, missing summary, or active failures.
4. **Complete transactional rollback backup**:
   - Creates consistent SQLite snapshot via `/usr/lib/open-hotspot/backup.sh export`.
   - Archives configuration, database, runtime code, both service init files, LuCI views, and installed APK metadata with strict error handling (no `|| true`).
   - Verifies all required members and archives with mode 0600.
   - Separates rollback paths: `r60`/openNDS 10.3.1-r3 is the official production baseline; `r90`/`r91` with openNDS 11.0.x are previous field candidates. Installed package identity is read from the version file, packaged Makefile, offline installed APK listing, or the local `/lib/apk/db/installed` record; description/size-only output is rejected and no repository refresh is allowed. Unknown or mismatched target state aborts before the archive or package transaction.
5. **Remote checksum verification**: Validates that the remote file SHA-256 matches the local verified checksum before invoking the package manager.
6. **Conditional installation**: Executes `apk add --allow-untrusted` only after all prior barriers pass.
7. **Post-install verification**: Executes `preflight.sh`, `diagnose.sh`, and `ndsctl status`.
8. **Explicit acceptance state**: Reports `Pending Hardware Validation`; physical client stability testing (10-15 min continuous traffic) remains mandatory before closing T006/T086.

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
and exact package SHA-256 to `docs/archive/evidence/field-evidence-YYYYMMDD.md`. Update the
matching row in [`integration-gap-register.md`](integration-gap-register.md),
`release-acceptance-matrix.md`, and `release-gates.md` in the same change.

The physical gate remains open until the fresh phone flow proves the entire
chain. Automated tests and isolated callback tests prove the implementation;
they do not replace the real-router client evidence.
