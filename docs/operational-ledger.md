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

| OP-006 | 2026-09-20 | Close/accounting probe | Acceptance target | First deauth probe failed in local command parsing before reaching SSH | failure | implementation | Do not infer a target result from a locally malformed probe; use the recorded status parser and record whether mutation was issued. | No target mutation occurred | Evidence pending |
| OP-007 | 2026-09-20 | r71 post-install reconciliation | EA8300/openNDS 11 | Read-only report observed zero live openNDS clients with one active SQLite session | partial | evidence | Treat as T011 stale-session evidence; do not mark the runtime chain green until close/restart policy reconciles it. | r71 diagnostic output; no credentials or client identifiers recorded | Pending Hardware Validation |

| OP-008 | 2026-09-20 | r72 adapter validation | EA8300/openNDS 11 | Installed versioned adapters and reran read-only diagnostics through the known tar-over-SSH path | success | environment | Reuse tar-over-SSH and require the versioned adapter check on future package installs. | r72 APK checksum; openNDS 11.0.0; FAS/uhttpd healthy; stale-session warning retained | Verified; T011 open |
| OP-009 | 2026-09-20 | r73 diagnostic contract | EA8300/openNDS 11 | Added an explicit packaged check that the daemon resolves to its versioned adapter | success | implementation | Require `adapter=versioned-opennds-contract` in every post-install report. | Repository and shell contract tests pass; target report shows adapter contract OK; stale-session warning retained | Verified; T011 open |

## Current known facts

- The target transport path is SSH plus `tar`; the target does not provide
  `sftp-server`.
- The package is address-independent. Any displayed LAN address is field
  evidence only, not a configuration contract.
- `diagnose.sh` is read-only and is the first post-install command.
- A live session and live openNDS byte counters do not close the persistent
  accounting gate until the close callback creates a SQLite usage event.
