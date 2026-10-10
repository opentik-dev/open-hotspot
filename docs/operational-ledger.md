# Open-HotSpot operational ledger

This is the active operational record. Add new target operations here using
the status vocabulary from [`source-of-truth.md`](source-of-truth.md).
Historical rows are archived at
[`archive/operations/operational-ledger-history.md`](archive/operations/operational-ledger-history.md)
and must not be used as current instructions.

## Current deployment truth — 2026-10-10

- Candidate: Open-HotSpot `1.2.0-r112` on Linksys EA8300 / openNDS 11.0.0.
- Artifact r112 reproducible SHA-256 `cb992b6063b7aa918a0d2b4da7567d5613892fcc34074b223157e1e884f845d5`.
- Captive plane: dedicated `br-hotspot`; service-plane lookup correction is
  implemented and tested.
- Release state: physical acceptance gates remain open; no production claim.
- Rollback: `r111` immediate checkpoint; `r60` protected cross-version path.

## Current entries

| ID | Date | Result | Evidence | Status |
|---|---|---|---|---|
| OP-203 | 2026-10-10 | Family Captive declarative collision contract hardened | `tests/test_family_captive_lab_contract.sh` | Implemented and Tested; runtime/FAS field validation pending |

Do not record credentials, FAS keys, router backups, or raw live-client data.
