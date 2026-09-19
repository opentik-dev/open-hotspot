# Open-HotSpot working guidance

Read `specs/001-open-hotspot/spec.md`, `plan.md`, `research.md`, and `tasks.md`
before changing implementation. The project follows the constitution in
`.specify/memory/constitution.md`.

Phase 0 gates T001–T013 are still open. Do not guess openNDS BinAuth/FAS
arguments, quota units, session identity, or `ndsctl` syntax. BinAuth must not
call `ndsctl`; new authentication and unverified adapters must fail closed.

The current implementation focus is the Phase 1 SQLite/domain foundation under
`starter-kit/root/usr/lib/open-hotspot/`. Run these checks before handoff:

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
```

Spec Kit is initialized with the generic integration because `.agents/` is
managed read-only in this workspace. Its command files are in
`.specify-commands/`; the CLI is `specify`.
