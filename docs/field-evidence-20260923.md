# Field evidence — 2026-09-23

This record covers the staged developer-pilot migration on the primary
EA8300. It is not a production acceptance record and contains no PINs, FAS
keys, Wi-Fi keys, private keys, or raw client identifiers.

## Primary-router staged migration

- Transport: laptop Wi-Fi to the discovered primary LAN address.
- Hardware/firmware: Linksys EA8300, OpenWrt 25.12.5, `ipq40xx/generic`,
  `arm_cortex-a7_neon-vfpv4`.
- Before mutation: openNDS 10.3.1 was installed; `dnsmasq-full` and `nftset`
  were already available; 2.4 GHz Wi-Fi was enabled and the 5 GHz radio was
  disabled in the existing configuration.
- Backup: a target configuration archive was created outside Git and its
  local/remote SHA-256 matched. The archive is intentionally not committed.
- Package result: openNDS 11.0.0-r1 and Open-HotSpot 1.2.0-r90 installed;
  `luci-compat` was resolved by APK. The openNDS package was built for the
  exact EA8300 package architecture.
- Initial failure: r90 base setup rejected the pre-existing old database as
  unversioned. The database was quarantined under a rollback filename rather
  than deleted, and a fresh r90 database was initialized.
- Second failure: openNDS 11 refused the old anonymous v10 UCI section with
  `invalid config format`. The package-provided named v11 section was adopted
  after the backup; this is recorded as INT-031.
- Final platform state: base setup `BASE_READY`; local FAS enabled; FAS uses
  `status.client`, port 2080, `/nds/fas.php`, secure level 1; custom BinAuth
  hook is installed; `diagnose.sh` reported `failures=0 warnings=0`.
- Direct client probes: port 2050 returned HTTP 511, and the local FAS
  endpoint returned the expected HTTP 400 for a bare request. A direct
  `neverssl.com` probe timed out, so external Internet acceptance is still
  pending a clean phone session and must not be inferred from the local
  listener result.
- Wi-Fi note: the 2.4 GHz AP is active on LAN. The 5 GHz radio remains
  disabled from the pre-existing router configuration; enabling it is a
  separate, reversible Wi-Fi change and was intentionally not mixed into the
  package migration.

## Unit-display decision

The database and openNDS adapter continue to use canonical units: seconds,
bytes, and kbit/s. Human-friendly selectors for minutes/hours/days, B/KiB/MiB/
GiB, and bit/s/kbit/s/Mbit/s/Gbit/s should be introduced as a separate r91
UI change, converting to canonical units at the LuCI/RPC boundary. This keeps
quota accounting and v11 contracts stable and avoids invalidating r90 field
evidence during the migration pilot.

## Gate status after this session

- T006: partially verified on the test candidate for download cutoff and
  callback accounting after r90; upload cutoff remains open.
- T011: partial; stale native restore containment is verified, but the full
  restart/reboot/dedup matrix remains open.
- T052/T087: open; interrupted setup and recovery are not yet evidenced.
- T086: open; failure-containment injection is not yet evidenced.
- T088/T090: open; clean factory acceptance and release freeze are not yet
  evidenced.

## Return to the disposable test router

The test router was reached again over Ethernet at its currently discovered
management address. It reports slot 02, openNDS 11.0.0-r1, Open-HotSpot r90,
`BASE_READY`, local FAS enabled, dnsmasq-full/nftset available, and a clean
diagnostic (`failures=0 warnings=0`). The disposable acceptance profile is
currently set to 600 seconds, 4 MiB upload, unlimited download; the intended
account is attached to that profile and has no active session. This is the
controlled preparation for the remaining T006 upload-direction proof, not the
proof itself.
