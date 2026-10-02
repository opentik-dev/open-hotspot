# Open-HotSpot current state

**As of:** 2026-10-03

This is the short operational truth for agents and release reviewers. The
specification, release-gate register, and field evidence remain authoritative
for detailed acceptance decisions.

## Baselines

| Role | Package/openNDS | Purpose | Status |
|---|---|---|---|
| Current field candidate | Open-HotSpot r93 / openNDS 11.0.0 | EA8300 candidate slot 02; guarded deployment completed | Installed successfully; UI separation present; post-install preflight/diagnostic/`ndsctl status` passed; hardware acceptance pending |
| Previous candidate | Open-HotSpot r92 / openNDS 11.0.0 | Previous target state | Superseded by r93 |
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

## 2026-10-02 audit checkpoint

The supplied read-only target probe reached the EA8300 at the operator's
management address and confirmed OpenWrt 25.12.5, openNDS 11.0.0, local FAS,
the versioned adapter, and a current `preflight.sh` result of `topology=ok`.
The UCI `setup_state=PREFLIGHT_FAILED` value is stale state from an earlier
attempt; it was not edited by hand and must be reconciled only through the
bounded setup/status path after backup approval.

The packaged diagnostic reported zero failures and warnings, but raw target
logs still contain `Dnsmasq reload failed`, a `preemptivemac quiet` failure,
routing-configuration retries, and a missing temporary client-state file. The
target also records recurring `session_reconcile_failed` and
`policy_refresh_failed` events. A live authenticated session remained
authenticated beyond the reported 3–4 minute interval during this observation,
so the user-facing eviction is not yet reproduced and must not be attributed
to a timeout or quota without a controlled account-specific test.

The installed r93 candidate provides implementation for
session lifecycle stability, reproducible APK packaging (clean git archive build
verified with SHA-256 `a93ab78f04315017c2c4e0fd1d5ac5595024634de8d9d31b5c86aafb0ad655db`),
reconciled release metadata, separated read-only DEV/Events LuCI surfaces, and
safe reconciliation/policy-refresh event reporting. Cycle stability tests in
the test suite are simulation/contract tests of algorithm logic. Its artifact
was installed on the target through the guarded deployment driver and passed
post-install diagnostics. A real client remained authenticated beyond the
reported 3–4 minute window; quota, restart, and failure-containment evidence
remain pending.

## 2026-10-03 deployment checkpoint

The guarded driver upgraded the target from r92 to r93 after creating the
SQLite export and complete rollback archive. The remote checksum matched the
local artifact `bd63507327ec167dc01075a71ab3d963beb77f09c9b69f797cd6818d9a11bd8a`.
Post-install diagnostics reported `failures=0 warnings=0`, and
`ndsctl status` reported a healthy openNDS 11.0.0 service. The 3–4 minute
client-eviction observation remained stable beyond 35 minutes, so the specific
reported eviction was not reproduced; remaining release gates are still open.

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
- The report-driven r74/r75/r76/r77/r78 changes are target-tested; r79
  contains the service-enable correction, r81 adds backup/state hardening, and
  r82 adds the dependency/Wi-Fi boundary checks:
  the period helper is now the single boundary source, renewal state is used by
  every policy path, and manager SQLite calls share timeout/foreign-key rules.
r86 includes an executable openNDS 11 reauthentication compatibility bridge,
r87 contains native restores that are not backed by manager SQLite when
Restore is disabled, r88 corrected the optional-file success return in the
database hardening path, r89 fixes the source-compatible reauth bridge, and r90 accepts the target's explicit quota-deauth callback names. An intermediate probe found rollback slot 01 with
r60/openNDS 10.3.1; the official Advanced Reboot path then returned the target
to candidate slot 02, which was jointly verified as the openNDS 11.0.0 candidate. A
later read-only probe has one pending-auth integration warning and still needs
a fresh phone login. Quota, restart, failure-containment, and
factory-acceptance evidence remain required.
