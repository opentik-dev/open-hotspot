# Field evidence — openNDS v11 FAS correction

**Date:** 2026-09-20
**Target:** Linksys EA8300, `boot_part=2`, OpenWrt 25.12.5, `ipq40xx/generic`
**Target address observed during this run:** `192.168.2.1`
**Packages:** openNDS 11.0.0, Open-HotSpot 1.2.0-r70, dnsmasq-full 2.93
**r63 APK SHA-256:** `14ef1bf5f93e9fcf9b53df5465496e7ea5e60b8dda86124bce05649a089d10c1`
**r66 APK SHA-256:** `c5caeae7302c5f9446e1ced57588fa76202b8053139e53951179740be75fb83d`
**r70 APK SHA-256:** `77c87c184b17f8d609c56ddf833971c881fd9f9a6f5640af4967bf34b65a7f28`

## Observed failure before r61

The client reached openNDS, but the screenshots showed the built-in
ThemeSpec/PreAuth pages (`Welcome`, `Continue`, and the openNDS session page)
instead of the Open-HotSpot username/PIN form. The target log identified the
cause:

```text
Preauth is Enabled - Overriding FAS configuration.
```

The client was therefore not evidence of a successful Open-HotSpot account
login. The later access to `https://192.168.2.1/cgi-bin/luci/` also cannot be
used as proof of a captive-portal bypass: HTTPS to a router management service
is a separate management path, and an already authenticated openNDS client has
the configured `allow all` authenticated policy.

## Correction

`activate-local-fas.sh` now sets `login_option_enabled='0'` when enabling the
local FAS. This selects the configured FAS instead of the default openNDS
ThemeSpec flow. The change is shipped in r61 and is covered by the local-FAS
contract test.

## Target verification after r61

- `boot_part=2` remained current.
- r61 installed successfully.
- `login_option_enabled=0` is present in the active openNDS UCI section.
- r62 installed successfully and `dhcp_default_url_enable=1` is present in
  the active openNDS UCI section.
- `ndsctl status` reports `ThemeSpec: Disabled` and secure FAS enabled.
- openNDS and uhttpd are running.
- The FAS key was not printed, exported, or committed to the repository.

## r63 root-cause correction

The actual phone/laptop evidence exposed a separate openNDS 11 behavior. With
`login_option_enabled=0` and both `fasremoteip` and `fasremotefqdn` absent,
openNDS deliberately renders `Remote Portal Not Defined`. The browser then
showed the openNDS return endpoint on port 2050 and a 404 for `/nds/fas.php`;
port 2050 is not the PHP FAS listener.

The r63 activation contract sets `fasremotefqdn=status.client`, leaves
`fasremoteip` unset, and keeps `fasport=2080` with `faspath=/nds/fas.php`.
After applying this correction on the isolated target, `status.client`
resolved to the current LAN gateway and `ndsctl status` reported the FAS URL
with hostname `status.client` and port `2080`. No LAN or WAN address is stored
in the package or UCI FAS contract.

The r63 APK installed successfully on the target and the service was brought
back to `running`. The target then reported the phone as an openNDS
`preemptive`/`Authenticated` client, proving that the redirect path no longer
ended at the 2050/404 endpoint. The manager database still showed one
`pending` authentication transaction and no active manager session, so the
credential-entry and BinAuth/accounting gate remains open until a clean phone
login is completed.

`dnsmasq` is running, `dnsmasq --test` passes, and its generated runtime state
contains the dynamic `status.client` address and DHCP option 114. The
openNDS log still emits `Dnsmasq reload failed!` during startup, but dnsmasq
subsequently rereads the generated host/DHCP state and resolves
`status.client`; this warning is recorded separately from the closed 2050/404
FAS routing defect.

## BinAuth/SQLite gap found after the portal retest

The later LuCI screenshots exposed a different defect: openNDS showed the
phone as `Authenticated`, while the manager dashboard still showed zero live
sessions and the Devices table was empty. A sanitized target query recorded
two `auth_transactions` rows in `pending`, zero devices, and zero active
sessions. The callback log contained both `auth_client` and `client_auth` for
the same client, so the portal had completed its handoff but the manager
adapter had not been loaded.

The exact target contract was then replayed against a temporary copy of the
SQLite database. The installed `/usr/lib/open-hotspot/binauth.sh` consumed the
pending transaction and created one device and one active session when called
directly. The stock `/usr/lib/opennds/binauth_log.sh` left the temporary copy
unchanged. Inspection of the openNDS 11 `ndscfg` wrapper showed why: with
non-tty stdin it reads stdin and resets its command-line arguments, so
`ndscfg get_option_from_config custombinauth` returned empty inside the stock
dispatcher. The dashboard gap was therefore a dispatcher configuration
failure, not a MAC, FAS-key, or SQLite matching failure.

r66 closes this implementation gap by setting
`custombinauth=/usr/lib/opennds/custombinauth.sh` during explicit local-FAS
activation and applying a narrow, recoverable UCI fallback in the stock
dispatcher. It does not replace the stock `binauth_log.sh`, call `ndsctl` from
BinAuth, or store a router address. r66 also maps finite remaining time to the
verified stock variable `sessiontimeout` rather than the unused
`session_length`. The live-client proof must be repeated
after r66: one fresh login must show a consumed transaction, one device, one
active session in LuCI, and the close callback must create usage history.

## r70 packaged diagnostic verification

r70 was installed on the same disposable target using the SSH `tar` fallback
because the target image has no `sftp-server`. The package upgrade completed
without changing the FAS address contract. The packaged read-only diagnostic
then returned `diagnostic_rc=0` with these sanitized facts:

- openNDS is running and reports version 11.0.0.
- `fasremoteip` is unset; both FAS and gateway FQDNs are `status.client`.
- uhttpd is running and listens on port 2080.
- The bare local FAS request returns the expected HTTP 400 (the endpoint is
  reachable but has no openNDS query payload).
- SQLite currently reports one active device and one active manager session.

The active device/session in this report is not counted as fresh acceptance
evidence because it was already present during the upgrade run. The fresh
phone flow, close callback, usage event, quota cutoff, and reboot/restore
policy must still be captured separately. The diagnostic is now in the APK
and is the first command to run after a factory-reset install.

The diagnostic implementation exposed and corrected three diagnostic-only
defects during this run: r68 treated the expected bare-request HTTP 400 as a
transport failure; r69 created its temporary directory too late; and r70
preserved the BusyBox wget status text needed to distinguish HTTP 400 from no
response. The final r70 field run passed.

## Still pending

The phone must reconnect to the SSID with WARP/VPN and mobile data disabled,
open an HTTP URL, and complete the Open-HotSpot account flow. The test must
record the FAS page, account login, `Authenticated` state, and post-login
Internet result. A separate reboot test remains required.

The first Android attempt occurred while openNDS was still restarting after
the package/configuration change. DHCP and Wi-Fi became available before the
openNDS firewall redirect was ready, so the Android assistant opened the
gateway address and displayed HTTP 404. r62 makes DHCP option 114 explicit;
the retest must still be performed after the service reports ready.

## Router and device policy

The shared `br-lan` must not receive the router-admin deny rule because it is
also the management path. The supported isolation path is a separate UCI
client/IoT network and SSID, followed by the LuCI router-access policy. Tapo
devices, the D-Link plug, and Android TV/atvtools are recorded as exception
requirements; no implicit MAC bypass was enabled because the exact openNDS v11
trusted/preemptive-device contract is not yet accepted.

**Release status:** `Pending Hardware Validation` for live FAS login, isolated
router-admin deny, device exceptions, and reboot persistence.
