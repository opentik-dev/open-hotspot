# Development guide

Open-HotSpot uses specification-driven development, but Spec-Kit is an
engineering tool rather than the product identity.

## Reading order

1. [`AGENTS.md`](../AGENTS.md) — shared agent contract.
2. [`constitution.md`](../.specify/memory/constitution.md) — non-negotiable
   architecture and delivery rules.
3. [`spec.md`](../specs/001-open-hotspot/spec.md) — product requirements.
4. [`plan.md`](../specs/001-open-hotspot/plan.md) — implementation boundaries.
5. [`research.md`](../specs/001-open-hotspot/research.md) — verified target
   facts and unresolved gates.
6. [`tasks.md`](../specs/001-open-hotspot/tasks.md) — work and gate status.
7. [`project-status.md`](project-status.md) and the relevant evidence/runbook.

## Change protocol

Keep product changes, engineering decisions, and field evidence separate:

```text
requirement → plan/task → implementation → automated test
           → target evidence → acceptance decision
```

Do not close a task merely because a file exists or a unit test passes. Do not
rewrite old evidence to make a new result look historical. Add a dated record
and link it from the relevant gate.

## Required local checks

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
for test in tests/test_*.sh; do sh "$test"; done
```

## Current compatibility boundary

The accepted implementation boundary is the target contract documented for
openNDS 10.3.1-r3. The openNDS 11 effort is governed by
[`ADR-003-opennds-v11-migration.md`](decisions/ADR-003-opennds-v11-migration.md)
and [`opennds-v11-contract.md`](opennds-v11-contract.md). It must not be mixed
into a production fix for the r60 baseline.
