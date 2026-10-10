# Open-HotSpot documentation

Use this page as the entry point into the repository. The project separates
product behavior, engineering design, field operations, and release evidence.

## Choose a path

| If you want to… | Start here |
|---|---|
| Understand the product | [`README.md`](../README.md) |
| Use the administrator flow | [`user/getting-started.md`](user/getting-started.md) |
| Install or accept a target | [`factory-reset-acceptance-runbook.md`](factory-reset-acceptance-runbook.md) |
| Develop and run checks | [`development.md`](development.md) |
| Understand the system architecture | [`architecture/overview.md`](architecture/overview.md) |
| Understand the current state | [`current-state.md`](current-state.md) and [`project-status.md`](project-status.md) |
| Review architecture decisions | [`decisions/`](decisions/) and [`../specs/001-open-hotspot/`](../specs/001-open-hotspot/) |
| Inspect release readiness | [`release-gates.md`](release-gates.md), [`release-acceptance-matrix.md`](release-acceptance-matrix.md), and [`delivery-manifest.md`](delivery-manifest.md) |
| Trace a claim to its proof | [`release-acceptance-matrix.md`](release-acceptance-matrix.md) |
| Review target evidence | [`field-evidence-20261003.md`](field-evidence-20261003.md) and [`operational-ledger.md`](operational-ledger.md) |

## Source-of-truth rule

- Requirements live in the specification and constitution.
- Implemented behavior is established by source code and automated tests.
- Target behavior requires field evidence on the exact OpenWrt/openNDS build.
- Release readiness is decided by the release gates and delivery manifest.
- Historical operations remain in the operational ledger and must not be
  rewritten to make the current candidate appear older or more complete.

The current candidate is `1.2.0-r112`; production acceptance remains pending.
