# Contributing to Open-HotSpot

Contributions are welcome in the LuCI interface, openNDS integration,
documentation, tests, and validation on additional OpenWrt hardware.

## Before changing code

Read [`AGENTS.md`](AGENTS.md), the constitution, and the relevant files under
`specs/001-open-hotspot/`. Do not guess openNDS callback arguments, quota units,
session identity, or `ndsctl` syntax. Record a decision when behavior is not
verified on the target.

## Before opening a pull request

Run:

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
for test in tests/test_*.sh; do sh "$test"; done
```

Explain the requirement, implementation, tests, field evidence, and remaining
risks. Do not mark hardware-only tasks complete from local tests. Do not commit
PINs, FAS keys, router backups, or live client data.

## Pull requests

Use a focused branch and a clear commit/PR description. Changes affecting the
openNDS contract, schema, security boundary, package dependencies, or release
gates require corresponding documentation and regression coverage. Keep the
r60 baseline reversible while working on the openNDS 11 migration track.
