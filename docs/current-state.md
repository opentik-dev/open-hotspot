# Open-HotSpot current state

**As of:** 2026-09-20

This is the short operational truth for agents and release reviewers. The
specification, release-gate register, and field evidence remain authoritative
for detailed acceptance decisions.

## Baselines

| Role | Package/openNDS | Purpose | Status |
|---|---|---|---|
| Current acceptance candidate | Open-HotSpot r74 / openNDS 11.0.0 | EA8300 `boot_part=2` field validation | Period/accounting consistency candidate; r73 remains the last installed field checkpoint |
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
| T011 | Partial | openNDS restart and router reboot tested separately, including restore policy and usage deduplication |
| T086 | Open | Existing authorization survives manager/BinAuth/cycle failure while new auth fails closed |
| T052/T087 | Open | Interrupted setup/upgrade rerun and service health proof |
| T088/T090 | Open | Full clean-hardware acceptance and release freeze |

## Known operating paths

- Target transport: SSH plus `tar`; do not retry `scp` when `sftp-server` is
  absent.
- First post-install check: `/usr/lib/open-hotspot/diagnose.sh`.
- A live openNDS byte counter is not persistent manager accounting until the
  close callback is observed.
- Any displayed LAN address is field evidence only. No package contract uses a
  fixed router address.
- The report-driven r74 changes are source-tested but not yet target-verified:
  the period helper is now the single boundary source, renewal state is used by
  every policy path, and manager SQLite calls share timeout/foreign-key rules.
