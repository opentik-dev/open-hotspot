# Open-HotSpot agent working agreement

This file is the shared operating contract for Codex, Claude, Gemini, and any
other agent working in this repository. It does not replace the specification;
it explains how an agent must use the specification and report its work.

For target operations, packaging, field acceptance, and release publication,
also use the project skill at
`skills/open-hotspot-ops-governance/SKILL.md` and append outcomes to
`docs/operational-ledger.md`. Known environmental failures must not be retried
without a changed variable and a recorded reason.

## Source of truth

Before changing implementation, read:

1. `.specify/memory/constitution.md`
2. `specs/001-open-hotspot/spec.md`
3. `specs/001-open-hotspot/plan.md`
4. `specs/001-open-hotspot/research.md`
5. `specs/001-open-hotspot/tasks.md`
6. `docs/project-status.md` and the relevant acceptance/gate documents

If two documents disagree, stop and record the conflict. Do not silently make
the code, task list, or evidence agree by editing whichever file is easiest.

## Non-negotiable engineering rules

- openNDS remains the captive-portal and traffic-enforcement engine.
- BinAuth must not call `ndsctl`, manipulate the firewall, or poll.
- Do not guess BinAuth arguments, FAS variables, quota units, session identity,
  or `ndsctl` syntax. Unverified adapters fail closed.
- New authentication fails closed when identity, policy, or credential state is
  unavailable; existing authorized sessions are not destroyed merely because
  the manager failed.
- SQLite accounting, voucher redemption, and device admission remain
  transactional and idempotent.
- Never place PINs, FAS keys, router backups, or live credentials in Git,
  diagnostics, commits, or agent output.
- Do not claim a physical-router result from a mock, static contract test, or
  screenshot alone.
- Do not mark a task `[x]` unless its implementation, required automated test,
  and required field evidence are all identified. Hardware-only gates remain
  `Pending Hardware Validation` until the evidence is recorded.
- Do not upgrade openNDS in place on the acceptance router. The v1.2/r60
  target remains the rollback baseline while the v11 work is isolated.

## Work protocol

For every change:

1. State the task, acceptance criterion, and files in scope.
2. Inspect the current implementation and relevant evidence before editing.
3. Make the smallest reversible change that satisfies the criterion.
4. Run the narrowest relevant checks, then the required repository checks.
5. Record failures as failures; do not reinterpret them as success.
6. Update the status/evidence document when the change affects a gate.
7. Report changed files, tests, evidence, remaining blockers, and rollback.

Use these status terms precisely:

| Status | Meaning |
|---|---|
| Implemented | Code or documentation exists. |
| Tested | Automated or isolated test passed. |
| Verified | Behavior was reproduced on the target environment. |
| Accepted | The requirement and its release evidence are complete. |
| Pending Hardware Validation | Code is present but a real-router proof is required. |
| Blocked | A named dependency or failure prevents progress. |
| Superseded | Replaced by a later approved decision. |

## openNDS v11 rule

The proposed v11 migration is a compatibility project, not a package swap. It
must use a separate decision record and adapter contract, build for the exact
target architecture, and pass FAS, BinAuth, UCI, quota, counter, restore, and
startup tests before any target installation. The v1.2 implementation remains
the rollback path until that evidence exists.

## Required checks before handoff

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
```

Run the full `tests/test_*.sh` contract set when touching an adapter, setup,
packaging, security boundary, or release documentation. Keep `.agents/`
read-only assumptions intact; shared instructions belong here.
