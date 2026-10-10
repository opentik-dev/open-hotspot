# Open-HotSpot current state

**As of:** 2026-10-10

This is the short operational truth for agents and release reviewers. The
specification, release-gate register, and field evidence remain authoritative
for detailed acceptance decisions.

## Baselines

The current installed and source field candidate is r112. It corrects the
openNDS 11 `setup`-section lookup used by the service-plane guard and is
verified on the dedicated `br-hotspot` plane. r111 remains the immediate
rollback checkpoint; r60 remains the protected cross-version rollback baseline.

Account switching and device lifecycle behavior are governed by the source
contracts and automated tests. They do not close any physical release gate by
themselves; target evidence remains tracked in the release matrix and ledger.

| Role | Package/openNDS | Purpose | Status |
|---|---|---|---|
| Installed field candidate | Open-HotSpot r112 / openNDS 11.0.0 | EA8300 candidate on dedicated `br-hotspot` | Target UCI lookup and service-plane health verified; multi-plane acceptance pending |
| Source candidate | Open-HotSpot r112 / openNDS 11.0.0 | Reproducible installed candidate | Fail-closed service-plane guard reads the target `setup` section; production acceptance pending |
| Previous candidate | Open-HotSpot r111 / openNDS 11.0.0 | Immediate rollback checkpoint | Devices stylesheet cache-bust; preserve as rollback |
| Rollback baseline | Open-HotSpot r60 / openNDS 10.3.1-r3 | A/B recovery and compatibility comparison | Preserved; do not upgrade it in place |

The two baselines are not interchangeable. A result from r60/openNDS 10.3.1
cannot close an openNDS 11 gate, and a v11 change must not overwrite the r60
rollback path.

## Versioned adapter contracts

The package now carries:

- `opennds-v10.3.1-r3.sh` for the rollback contract;
- `opennds-v11.0.0.sh` for the current `status.client` local-FAS contract.

`opennds.sh` detects the installed openNDS version from `ndsctl status`, loads
the matching contract, and rejects unknown versions. The shared adapter still
owns only verified `ndsctl` syntax and native units; BinAuth remains separate
and cannot call it.

## Verified runtime chain

The latest physical evidence proves:

`FAS → BinAuth → SQLite device/session → LuCI Devices/Dashboard`

The client appears as an active device and live session, and openNDS reports
authenticated traffic. This is `Verified` for the live-session boundary.

It is not yet `Accepted` for persistent accounting: the close callback must
create one deduplicated `usage_events` row, and the quota test must prove
counter direction and cutoff.

If SQLite reports an active manager session while openNDS reports zero live
clients, the diagnostic emits
`manager-active-session-without-opennds-client`. Treat this as a restart or
close-callback reconciliation issue under T011, not as a healthy session.

## Remaining runtime gates

| Gate | Current state | Closure evidence |
|---|---|---|
| T012 | Partial / session boundary verified | Fresh login followed by close callback, consumed transaction, session close, and usage event |
| T006 | Open | Controlled upload/download traffic and measured native quota cutoff |
| T011 | Partial / Verified restore slice | openNDS restart and router reboot tested separately; disabled restore closes on reboot, enabled restore reapplies after client traffic and automatic cycle |
| T086 | Open | Existing authorization survives manager/BinAuth/cycle failure while new auth fails closed |
| T052/T087 | Open | Interrupted setup/upgrade rerun and service health proof |
| T088/T090 | Open | Full clean-hardware acceptance and release freeze |

## Historical audit evidence

Earlier r90–r111 probes, deployments, and failures remain preserved in the
dated field evidence and operational ledger. They are evidence of past states,
not current candidate status. Use the current gate table above for decisions.

## Backup evidence

The supplied manager archive was checked locally and on the EA8300 without
importing it: gzip/tar structure, exact member set, SQLite integrity, and
schema version all passed. The archive is now documented and exported with
private file permissions. Target import/rollback remains an open field gate;
this evidence does not make it a full-router backup.

## Known operating paths

- Target transport: SSH plus `tar`; do not retry `scp` when `sftp-server` is
  absent.
- First post-install check: `/usr/lib/open-hotspot/diagnose.sh`.
- A live openNDS byte counter is not persistent manager accounting until the
  close callback is observed.
- Any displayed LAN address is field evidence only. No package contract uses a
  fixed router address.
- The router-side Wi-Fi board-definition repair is verified. The packaged
  preflight now detects malformed `/etc/board.json`; phone visibility remains
  a physical acceptance check.
- Historical implementation and target checkpoints are retained in the
  release history and operational ledger; they are not repeated here.
- Quota, restart, failure-containment, and factory-acceptance evidence remain
  required for r112.
