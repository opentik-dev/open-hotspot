# Contributing to Open-HotSpot

## Before changing code

Read these files in order:

1. `AGENTS.md`;
2. `.specify/memory/constitution.md`;
3. `specs/001-open-hotspot/spec.md`;
4. `specs/001-open-hotspot/plan.md`, `research.md`, and `tasks.md`;
5. the relevant release gate in `docs/release-gates.md`.

Do not guess openNDS BinAuth arguments, quota units, session identity, or
`ndsctl` syntax. Capture target behavior in the research/evidence documents
before changing an integration adapter.

## Development checks

Run the same checks used by CI:

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
for test in tests/test_*.sh; do sh "$test"; done
```

The APK must be built from source with `sh tools/build-apk.sh` using the target
OpenWrt SDK. Do not commit generated SDK directories, private keys, router
backups, FAS keys, or real credentials.

## Pull requests

- use a focused branch and a descriptive commit/PR title;
- explain the requirement and release gate affected;
- add or update a contract test for behavior changes;
- record target-only evidence in `docs/field-evidence-20260918.md` or a new
  dated evidence file;
- update `docs/release-acceptance-matrix.md` when a gate changes;
- state whether the change is safe for upgrade, rollback, and factory-reset
  acceptance;
- do not mark a gate closed from source inspection alone.

All PRs require passing CI and review. Direct pushes to `main` are prohibited
by the repository branch-protection policy.
