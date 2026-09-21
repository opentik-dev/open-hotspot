---
name: open-hotspot-ops-governance
description: Govern repeatable Open-HotSpot router operations by reusing recorded transport, diagnostic, packaging, and acceptance outcomes instead of repeating known failures.
metadata:
  short-description: Prevent repeated router-operation failures
---

# Open-HotSpot operations governance

Use this skill for any factory-reset install, package transfer, openNDS/FAS
diagnostic, physical acceptance test, router reboot, A/B-slot action, or
GitHub release operation in this repository.

## Required memory lookup

Before touching the target, read:

- [`AGENTS.md`](../../AGENTS.md)
- [`docs/operational-ledger.md`](../../docs/operational-ledger.md)
- [`docs/integration-gap-register.md`](../../docs/integration-gap-register.md)
- [`docs/installation-and-integration-runbook.md`](../../docs/installation-and-integration-runbook.md)
- [`docs/release-gates.md`](../../docs/release-gates.md)

The ledger is operational memory, not a suggestion list. Reuse a recorded
successful path and do not retry a recorded failure unless the relevant
environmental fact or command has changed and the reason is recorded first.

## One-shot operating rules

1. Identify the operation and its acceptance gate before executing it.
2. Inspect the ledger for known transport and target capabilities.
3. Run one bounded probe before mutation. If it fails, classify the result as
   `environment`, `contract`, `implementation`, or `evidence`.
4. Use a known fallback immediately when the ledger contains one. For example,
   if the target lacks `sftp-server`, transfer an artifact with `tar` over the
   already verified SSH channel; never retry `scp` for that target state.
5. Permit at most one retry only when the probe identifies a changed variable.
   Otherwise stop, record the failure, and update the gap register.
6. After a successful mutation, run the smallest read-only health check and
   record both the result and the exact artifact checksum.
7. Distinguish `Implemented`, `Tested`, `Verified`, `Accepted`, and `Pending
   Hardware Validation`. A screenshot can prove a visible state, but cannot
   close an accounting, quota, reboot, or security gate without its specified
   field evidence.
8. Never record PINs, FAS keys, SSH private keys, router backups, tokens, or
   raw live-client identifiers. Sanitize MAC/IP data in committed evidence.

## Open-HotSpot acceptance boundary

Treat these as separate proofs:

- portal/FAS redirect;
- successful credential handoff and openNDS `Authenticated` state;
- manager SQLite transaction, device, and active session;
- close callback and persistent usage event;
- counter direction and quota cutoff;
- reboot/session-restore policy;
- client-network isolation from router administration.

Do not report the first three as proof of the fourth. When openNDS live
traffic counters are non-zero but the manager's persistent counters are zero,
the correct state is `session verified; close/accounting pending`.

## Recording rule

Append one entry to `docs/operational-ledger.md` after every target operation,
including a failed attempt. Use the schema in
[`references/ledger-schema.md`](references/ledger-schema.md). Link the entry
to the release gate and package checkpoint. If a failure is repeatable, add a
contract test or a runbook guard before declaring it closed.

## External publication

Before a Git push, inspect the diff, run the required repository checks, scan
for secrets, and verify that generated artifacts and live evidence are not
being published unintentionally. Push only after the user explicitly requests
publication; report the branch, commit, remote, and resulting revision.
