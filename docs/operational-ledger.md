# Open-HotSpot operational ledger

This is the active operational record. Add new target operations here using
the status vocabulary from [`source-of-truth.md`](source-of-truth.md).
Historical rows are archived at
[`archive/operations/operational-ledger-history.md`](archive/operations/operational-ledger-history.md)
and must not be used as current instructions.

## Current deployment truth — 2026-10-10

- Candidate: Open-HotSpot `1.2.0-r112` on Linksys EA8300 / openNDS 11.0.0.
- Artifact r112 reproducible SHA-256 `c2b0c6a5fbe7de36286a0731234f856c1c5aeef9c1140d036a8f304ae4c0ea30`.
- Captive plane: dedicated `br-hotspot`; service-plane lookup correction is
  implemented and tested.
- Release state: physical acceptance gates remain open; no production claim.
- Rollback: `r111` immediate checkpoint; `r60` protected cross-version path.

## Current entries

| ID | Date | Result | Evidence | Status |
|---|---|---|---|---|
| OP-203 | 2026-10-10 | Family Captive declarative collision contract hardened | `tests/test_family_captive_lab_contract.sh` | Implemented and Tested; runtime/FAS field validation pending |

Do not record credentials, FAS keys, router backups, or raw live-client data.
