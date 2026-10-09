# Open-HotSpot delegation context

This file is shared operational memory for delegated agents. It contains no
credentials, FAS keys, PINs, backups, or raw live-client identifiers.

## Scope

- Repository: Open-HotSpot LuCI manager.
- Current candidate: r89, OpenWrt 25.12.5 on Linksys EA8300, openNDS 11.0.0.
- Rollback baseline: r60/openNDS 10.3.1-r3; do not overwrite it.
- Target transport: SSH plus tar over SSH. The target has no `sftp-server`;
  do not retry SCP/SFTP.
- Router addresses are field facts only. Do not add fixed LAN/WAN addresses to
  code, packaging, or documentation contracts.

## Gate truth

- T006 quota/counter direction: open; requires real upload and download traffic
  and automatic cutoff evidence.
- T011 restart/reboot/dedup: partial; stale native restore containment is
  verified, but the complete matrix is open.
- T052/T087 interruption and recovery: open; needs physical interruption and
  recovery evidence.
- T086 failure containment: open; needs connected-client failure injection.
- T088/T090 factory acceptance/release freeze: open; no-go until all blockers
  are evidenced.

## Latest field observation

- Candidate slot 02 is the openNDS 11.0.0 candidate; r89 is the source-compatible
  reauth-bridge fix.
- A fresh post-r89 read-only check verified the live path: no pending
  authentication transactions, one active SQLite session, an openNDS
  `Authenticated` client, and non-zero live upload/download counters. The
  second openNDS client is a separate CPD `Preauthenticated` discovery client,
  not the authenticated session.
- The active SQLite session belongs to an unrelated unlimited test account;
  the intended quota account has no live session. Do not use this observation
  as T006 evidence. The next physical run must use the intended quota account
  after clearing the unrelated live client through the normal portal/session
  flow.
- The next T006 preflight later observed `active_sessions=0` and a single
  `Preauthenticated` openNDS client with native quotas unset; the intended
  account's latest row was closed. Treat this as a prerequisite observation,
  not a product failure, and require a live authenticated quota session before
  generating traffic.
- Account inspection found `opentik` had drifted to a 100MB/1000-kbit/s profile,
  not the disposable 4MiB acceptance profile. It was corrected through the
  official admin path; its current session was intentionally deauthenticated.
  The next login must verify approximately 4096 kB upload/download quota before
  any T006 traffic is generated.
- Refresh LuCI Dashboard and Devices after this evidence. Quota cutoff,
  restart/reboot/dedup, interruption recovery, failure containment, and factory
  acceptance remain open until their own field evidence is recorded.

## Agent boundaries

- Copilot test lane: inspect, run repository checks, and report findings. It may
  propose bounded changes only when explicitly requested; it must not commit,
  push, touch router credentials, or claim hardware acceptance.
- agy review lane: read-only release/diff review. It must not commit or push in
  the current run because the physical release gates are open.
- The orchestrator reviews every diff and reruns required checks.

## Delegation record

- Copilot's latest read-only run timed out during its authentication/version
  preflight and did not dispatch; no files or router state changed.
- agy's latest read-only release review completed with `HOLD FOR HARDWARE
  EVIDENCE`. It identified the required untracked package/specification files
  and documentation corrections; it did not edit, commit, or push.

## Required checks

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
for t in tests/test_*.sh; do sh "$t"; done
```

## Reporting contract

Reports must separate Implemented, Tested, Verified, Accepted, Pending
Hardware Validation, Blocked, and Superseded. A screenshot or static test
cannot close quota, reboot, failure-containment, or factory gates.
