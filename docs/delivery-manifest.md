# Open-HotSpot delivery manifest

**Candidate:** `luci-app-open-hotspot 1.2.0-r60`
**Artifact:** CI-generated APK attached to the matching GitHub Release
**SHA-256:** recorded beside the artifact by the release workflow
**Target checkpoint:** Linksys EA8300, OpenWrt 25.12.5, `ipq40xx/generic`, openNDS 10.3.1-r3.
**Decision:** Controlled pilot / factory-reset acceptance candidate; not yet a production baseline.

## Delivered

- SQLite schema and migrations through schema v4.
- Local FAS credential verification with fail-closed handling.
- Verified target-specific BinAuth parsing with no `ndsctl` call in BinAuth.
- Native openNDS policy adapter, periods, quota accounting, vouchers, and recovery helpers.
- LuCI profiles, accounts, devices, vouchers, history, dashboard, backup/import, Renew, and explicit MAC Reassign.
- Arabic and English portal templates.
- Package checks, schema checks, shell checks, quota checks, and target installation checks.
- The LuCI CSRF fix for the target dispatcher (`context.authtoken`) is included in r39.
- The Linksys EA8300 two-slot layout can be used as an A/B rollback boundary;
  the factory-reset runbook now treats slot 01 as candidate and slot 02 as
  protected recovery, with separate SSH identities and known-hosts files for
  each slot's currently discovered management address.
- r40 adds a local-FAS dynamic-address guard, r41 adds a preflight guard,
  r42 preserves the guard as a directly executable preflight command, r44
  discovers the live LAN interface, and r45 waits for the observed openNDS
  startup window, r46 keeps repeated FAS activation idempotent, r47 validates
  UCI list detection, r48 adds init-time readiness recovery, r49 makes the
  post-install setup path reproducible, r50 makes explicit FAS activation
  generate a target-local random key, and r51 makes its hex validation strict against
  duplicate/overlapping LAN/WAN topology. r52 adds the address-independent
  client-network router-admin deny policy, its LuCI/RPC control, a same-device
  lockout guard, and the WARP/IoT acceptance procedure in
  [`router-access-and-iot.md`](router-access-and-iot.md). r53 also removes the
  upgrade-time openNDS restart race, cleans stale runtime socket state during
  bounded recovery, and checks readiness from the periodic cycle. r54 waits for
  an already-starting openNDS process before attempting recovery, avoiding the
  S95 startup/firewall-hook restart race. r55 also makes router-access guard
  failures return nonzero before any firewall mutation. The package documents
  the supported upstream-Wi-Fi/Ethernet-management topology in
  [`topology.md`](topology.md).

## Evidence already available

The release artifact is built from source by CI and its SHA-256 is published
next to the APK in the matching GitHub Release; generated `dist/` output is
not a release input. The r60 source checkpoint includes the target-specific
procd stdout compatibility fix: the target reports stable `ndsctl` readiness
and a preauthenticated client is rejected by the openNDS nftables chain.
Schema migration
v4, RPC methods, PHP syntax, backup validation, and isolated Renew/Reassign
flows were verified. The full repository test suite passes:

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
for t in tests/test_*.sh; do sh "$t"; done
```

## Release blockers still requiring field evidence

These are deliberately not marked closed from source inspection alone:

| Gate | Required field evidence |
|---|---|
| T003/T012 | A disposable Wi-Fi client completes portal → FAS → openNDS authorization → BinAuth → close/accounting. |
| T006 | Controlled upload/download traffic maps counter direction and proves measured native cutoff. |
| T011 | openNDS restart and router reboot are tested separately for live-session behavior and persistent usage. |
| T052/T087 | Setup/package interruption and restart leave a healthy, repeatable router state. |
| T086 | Manager, BinAuth, and cycle failure behavior is tested with a connected client. |
| T088/T090 | The complete quickstart passes on the reset target and the evidence is recorded. |

The historical target evidence is recorded in E-009 through E-012 of
[`field-evidence-20260918.md`](field-evidence-20260918.md). Do not mark the
candidate as a production baseline while the openNDS service gate is open.

r59/r60 add the restore policy and target-specific live-client resolution. The
EA8300 field test now proves both paths: enabled restores the phone to
`Authenticated` after openNDS becomes ready, while disabled leaves it
`Preauthenticated` after reboot. The separate openNDS restart accounting and
SQLite usage-deduplication portions of T011 remain open.

The E-012 field test confirmed a real portal login and confirmed that reboot
recreates the openNDS service and preauthentication firewall. The authenticated
phone session was intentionally not restored after reboot and had to return to
the portal; this is fail-closed behavior under the current BinAuth setup, not a
production claim of live-session persistence. T011 remains open until the
separate openNDS restart, SQLite usage-persistence, and session-policy decision
evidence are attached.

The supplied clean-router procedure was tested in its OpenWrt `apk` form. The
target now has `dnsmasq-full` with `nftset` support and preserved DHCP/openNDS
configuration hashes, but that change did not resolve the openNDS
`exit_code=139`/dnsmasq-reload failure. r60 carries the proven init-wrapper
compatibility fix during both install and upgrade. The APK intentionally does not silently
replace dnsmasq or overwrite `/etc/config/opennds`; setup must preserve the
local FAS configuration and report this runtime blocker explicitly.

Run [`factory-reset-acceptance-runbook.md`](factory-reset-acceptance-runbook.md)
on a disposable router. Only after its evidence is attached to
`docs/release-gates.md` should the tasks be changed to `[x]` and r60 be
declared the v1.2 production baseline.

The first live A/B attempt is recorded in
[`field-evidence-20260918.md`](field-evidence-20260918.md). It proved the
partition discovery, backup, boot selection, and management-address transition.
The follow-up run restored SSH on the current slot and installed earlier
checkpoints; r60 is the source-built candidate, and live client gates remain
open until the acceptance matrix is completed.
