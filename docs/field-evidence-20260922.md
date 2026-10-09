# Field evidence — 2026-09-22

Target: Linksys EA8300, OpenWrt 25.12.5, openNDS 11.0.0, current slot
`boot_part=2`, management address discovered for this run as `192.168.2.1`.
The package does not store or require that address.

## r78 acceptance slice

- Transfer used SSH plus `tar`; `scp` was not retried because the target has no
  `sftp-server`.
- r78 installed successfully and the read-only diagnostic reported healthy
  openNDS, uhttpd, local FAS, and the versioned adapter.
- Direct Ethernet HTTP interception reached the local FAS: GET `200`, login
  POST `200`, openNDS handoff `307`.
- The target reported one Authenticated client and one active manager session;
  the dashboard/device boundary was therefore physically observed.
- The package deauth control returned success. After the target callback,
  openNDS clients changed from one to zero, active SQLite sessions from one to
  zero, and usage events increased from one to two.
- The latest usage event had method `ndsctl_deauth`; its byte counters were
  persisted. No PIN, FAS key, raw MAC, raw token, or backup is recorded here.
- Final diagnostic: `failures=0 warnings=0`, `fasremoteip=unset`,
  `fasremotefqdn=status.client`, openNDS `11.0.0`, and zero current clients.

## r80/r81 state and backup hardening

- The supplied manager archive passed local validation and target-side
  `backup.sh validate` without being imported. The target temporary copy was
  removed after validation.
- The archive is manager-state only: it contains the SQLite database and
  manager UCI policy, not network/openNDS/uhttpd/FAS configuration or router
  credentials. The scope is now documented in `docs/backup-and-restore.md`
  and in the LuCI Backup page.
- r80 installed successfully; r81 then installed successfully over the
  documented tar-over-SSH path. The target now reports `BASE_READY`, an empty
  setup error, a passing topology preflight, and a running openNDS/uhttpd/FAS
  diagnostic with zero failures and zero warnings.
- r81 corrected the target's permissive live-state modes: the manager database
  and UCI policy are now private to root. The target image lacks `stat`, so
  verification used the available `ls -l` output instead.
- No router address, FAS key, PIN, raw MAC, raw token, or backup payload is
  recorded here.

## r82 dependency and Wi-Fi boundary

- The target was checked before the r82 package build. `dnsmasq-full` was
  already installed and `dnsmasq --version` reported `nftset`; its omission
  from the core package plan was not the cause of the portal or Wi-Fi symptom.
- The core package remains free of an unconditional dnsmasq swap. r82 ships a
  conditional `dnsmasq-capability.sh` gate/install helper for openNDS
  autonomous blocklist/walled-garden features and reports the result in
  preflight/diagnostic output.
- The target's `/etc/board.json` was invalid JSON. The invalid file was
  preserved, OpenWrt `board_detect` regenerated a valid board definition, and
  `wifi reload` completed. Post-repair `wifi status` reported all radios up
  with the 2.4 GHz and 5 GHz AP interfaces enabled in the client bridge.
- Router-side Wi-Fi repair is `Verified`; phone discovery and captive-portal
  behavior still require a physical test with VPN/WARP and mobile data
  disabled. The root-password warning remains an acceptance blocker.

## r82 install verification

- r82 was installed over the recorded SSH-plus-tar transport path. The
  artifact SHA-256 is
  `4441c7db9bf0483f1f56b85d2c5e9e509eb93e0bb0f8c510a512598958a5b6f8`.
- Target preflight returned `rc=0`: topology is non-overlapping, board JSON is
  valid, `dnsmasq-full`/`nftset` is available, and openNDS 11.0.0 is reported.
  Setup remains `BASE_READY` with local FAS enabled and restore disabled.
- The packaged diagnostic returned zero failures but one warning because
  recent abandoned portal attempts left pending FAS transactions inside their
  normal 15-minute lifetime. They were not deleted or force-expired; the next
  diagnostic after expiry must confirm the warning clears.
- The package contents on the target include both
  `dnsmasq-capability.sh` and `wifi-board-recover.sh`. This proves packaging
  and router-side readiness, not phone discovery or the remaining runtime
  gates.

## New-account login boundary

- The new test account existed, was active, and its PIN matched the stored
  PBKDF2 record. FAS created pending transactions, proving that the rejection
  was not a username/PIN failure.
- BinAuth correctly refused the current client because its MAC was still owned
  by the previous acceptance account. This is the intentional anti-hijack
  policy, not a silent credential error.
- The current client had zero live manager sessions. The documented MAC
  Reassign operation was executed to the new account; old pending attempts
  were allowed to expire. A fresh phone login is required to close the
  physical session/accounting gate.
- For the next controlled acceptance, `opentik` is assigned to a temporary
  quota profile with a 600-second period and equal upload/download ceilings.
  This prepares T006; it does not prove counter direction or cutoff until
  traffic is generated from the phone.

## Latest physical phone evidence

- The supplied Devices screenshot shows the new test account attached to the
  phone device, with the device status `active` and no live session after the
  session ended. The previous acceptance account remains as a separate
  historical device row, as expected after explicit MAC reassignment.
- The supplied History screenshot contains a usage row for the new account
  with non-zero seconds and both byte directions. The Dashboard shows the
  same persistent totals with zero live sessions after logout. This verifies
  the physical portal → FAS → BinAuth → SQLite close path and the LuCI
  visibility boundary.
- The measured session used 85 seconds, 171,757 upload bytes, and 2,892,548
  download bytes against the temporary 600-second/262,144-byte-per-direction
  profile. Because the session was closed by an administrative/logout path and
  the log did not report `downquota_deauth`, this is not quota-cutoff proof.
  It proves that both counter directions were persisted; T006 remains open
  for a controlled automatic quota-deauth test.
- The target log also exposed the independent openNDS 11 reauth-helper path
  mismatch recorded as INT-026/OP-030. r84 adds an executable compatibility bridge; its
  warning-free callback verification is still pending.
- For the next T006 run, the disposable profile was changed from the earlier
  256 KiB ceiling to 4 MiB in each direction, with the same 600-second limit.
  This is a measurement setup so the portal handshake does not consume the
  whole quota; it is not a production policy or a quota result.
- The profile UI already exposes upload/download rates in kbit/s. No rate
  result is claimed from the current screenshots; rate acceptance remains a
  separate measured test after the quota path is stable.

## r85 Reassign diagnostics and access boundary

- The r85 architecture-neutral APK was rebuilt from source with SHA-256
  `2fb81486eb485b03f5452a0a0d15316076f8c899ea86e8820a73a50fbbb566a9`.
  Repository unit, shell, quota, PHP, and contract checks passed.
- The source candidate adds bounded Reassign reason codes. The previous LuCI
  `Error: validation` was not sufficient to distinguish a same-account row,
  live-session lock, inactive device, invalid target account, database error,
  or transaction conflict. No MAC ownership policy was relaxed.
- A new bounded SSH probe using the previously recorded administrator key was
  rejected with `Permission denied (publickey,password)`. The root password is
  reported by the operator as set, but this cannot be verified from the
  rejected channel. No further target mutation was attempted and no password
  or private key was recorded.

## r85-r88 target recovery and native-restore containment

- The operator restored an approved password SSH channel. r85 was installed
  through the recorded non-TTY tar-over-SSH path; two consecutive base setup
  runs returned `BASE_READY`, and the read-only diagnostic found no service or
  topology failure. `dnsmasq-full`/`nftset`, openNDS 11.0.0, uhttpd, and local
  FAS were present.
- The first post-r85 phone callback exposed an upstream openNDS 11 helper
  syntax fault: `check_reauth_interval.sh` used uppercase `If`. This is
  consistent with the upstream issue record and prevented the manager callback
  from completing. r86 applies only the exact lowercase correction and stores
  the original vendor file for rollback. The helper passed `sh -n` afterward.
- A bounded openNDS restart initially reported not-ready at 20 seconds, then
  became healthy after the target's normal long startup window. This is a
  timing observation, not a restart-gate pass.
- The phone then became `Authenticated` without a new manager session because
  native openNDS `auth_restore` restored a stale client from its own database.
  The manager reported zero active SQLite sessions and the diagnostic warned
  `opennds-authenticated-without-manager-session`; this was recorded as a
  real integration failure, not a login success.
- r87 adds fail-closed reconciliation for manager Restore=`disabled`: live
  native-restored clients are compared by MAC to active SQLite sessions and
  unknown ones are deauthenticated. The target returned to zero live clients
  with no database mutation beyond the existing pending transactions. A fresh
  phone login is still required to prove the new `auth_client` path.
- r88 was installed on candidate slot 02 after the database permission helper
  was corrected to return success when the optional host UCI path is absent.
  Base setup, reconciliation, preflight, and diagnostic all returned success;
  the diagnostic had no failures at that point. An intermediate probe briefly
  observed the rollback package with a shared stale host-key file; the official
  Advanced Reboot API was then used and the joint boot/package/openNDS probe
  returned candidate slot 02 with r88 and openNDS 11.0.0. A later bounded
  read-only probe returned failures=0 but warnings=1 because one pending
  authentication transaction had no manager session; the two observed clients
  were Preauthenticated and active SQLite sessions were zero. The physical
  client still needs a fresh login.
- No password, FAS key, PIN, raw token, raw MAC, or backup payload is recorded
  here.

## r88/r89 build and callback evidence

- Two consecutive `sh tools/build-apk.sh` runs for r88 produced the same
  SHA-256 (`16879aa7310729f72f78e8fa9d0a2df23e7047b9d3eb4e66defeee056c923c57`).
  The build fixes package timestamp metadata with `SOURCE_DATE_EPOCH` and UTC
  and normalizes staged file mtimes. This is repository/build evidence, not
  field acceptance evidence.
- r89 fixes the source-time `exec` trap in `/usr/check_reauth_interval.sh`.
  The corrected APK was installed through tar-over-SSH; a target shell probe
  confirmed that sourcing the bridge returns to the caller with the helper
  variables in scope. The target database before the fresh retest contained
  pending auth transactions and no active manager session, matching the
  diagnosed callback bypass. Fresh login evidence remains required.

## Root cause closed

## r84 reauth-helper bridge verification

- r84 was installed over the recorded SSH-plus-tar path. The packaged bridge
  exists at `/usr/check_reauth_interval.sh`, is executable, and delegates to
  the official helper under `/usr/lib/opennds`.
- Post-install preflight remained healthy: topology separated, board JSON
  valid, `dnsmasq-full`/`nftset` available, and openNDS 11.0.0 detected.
  The packaged diagnostic returned `failures=0 warnings=0`; no service or
  network restart was required for the package upgrade.
- Historical missing-helper messages remain in `logread`; a new callback is
  still required to prove that r84 removes the warning during live execution.

The r77 run exposed that the target's deauth callback carries the base64
marker for an empty custom field. r78 accepts only that explicit marker and
resolves the sole active session for the callback MAC in SQLite. Arbitrary or
unknown custom data still fails closed. The IP lookup in r77 remains required
for the target's `ndsctl deauth` control path.

## Gates still open

T006 still needs controlled upload/download quota cutoff evidence. T011 still
needs the separate restart/reboot matrix and duplicate-callback evidence, but
the r79 restore slice is now physically verified: the service was enabled with
two cron entries, reboot preserved the manager row, first client traffic made
the client visible, and automatic cycle restored `Authenticated` without a
new usage event. The final test configuration was returned to check interval
300 and restore disabled.
T052/T087, T086, T088, and T090 still require their physical acceptance
procedures. Internet reachability through the upstream WAN was not claimed in
this Ethernet-only probe because the host's default route is on another
interface; phone testing with VPN/mobile data disabled remains required.
