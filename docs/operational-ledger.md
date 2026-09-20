# Open-HotSpot operational ledger

This is the append-only memory of target operations that would otherwise be
repeated. It records reusable command paths and failure classifications while
excluding credentials, FAS keys, router backups, and raw live-client data.

| ID | Date | Operation | Target state | Attempt | Result | Classification | Reuse rule | Evidence | Gate status |
|---|---|---|---|---|---|---|---|---|---|
| OP-001 | 2026-09-20 | Transfer r67 APK | EA8300/OpenWrt; SSH reachable; no SFTP server | `scp` to target | failure | environment | Do not retry `scp` while `sftp-server` is absent; use `tar` over verified SSH and move the artifact on-target. | `sftp-server not found` | Tested failure path |
| OP-002 | 2026-09-20 | r68 FAS diagnostic | openNDS 11/uhttpd | Bare FAS request treated every non-zero BusyBox wget exit as failure | failure | contract | HTTP 400 for a bare FAS request is an expected endpoint response; distinguish it from transport failure. | r68 field run | Superseded by r70 |
| OP-003 | 2026-09-20 | r69 FAS diagnostic | openNDS 11/uhttpd | Probe log was opened before its temporary directory existed | failure | implementation | Create the diagnostic workspace before any probe redirects output. | r69 field run | Superseded by r70 |
| OP-004 | 2026-09-20 | r70 install/diagnostic | EA8300 `boot_part=2`; openNDS 11 | `tar` over SSH, APK upgrade, read-only diagnostic | success | environment | Reuse the tar-over-SSH transfer path for this target; do not attempt SFTP. | APK SHA recorded in release history; diagnostic `failures=0 warnings=0` | Verified |
| OP-005 | 2026-09-20 | Fresh portal session | Physical phone client | Portal login produced an openNDS `Authenticated` client, one manager device, and one active session | partial | evidence | Treat Devices/Dashboard visibility as session-integration proof; still run close, usage, quota, and reboot gates separately. | User screenshots at 07:48/07:52; live openNDS counters non-zero while persistent usage remained zero | Verified; accounting pending |

## Current known facts

- The target transport path is SSH plus `tar`; the target does not provide
  `sftp-server`.
- The package is address-independent. Any displayed LAN address is field
  evidence only, not a configuration contract.
- `diagnose.sh` is read-only and is the first post-install command.
- A live session and live openNDS byte counters do not close the persistent
  accounting gate until the close callback creates a SQLite usage event.
