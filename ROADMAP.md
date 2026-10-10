# Open-HotSpot roadmap

This roadmap describes the next verifiable outcomes. It does not replace the
release-gate register, field evidence, or the implementation task list.

## Current baseline

`1.2.0-r112` is the current installed/source field candidate for OpenWrt
25.12.5 and openNDS 11.0.0. It is a controlled pre-production candidate, not
an accepted production release. r111 is the immediate rollback checkpoint and
r60/openNDS 10.3.1-r3 remains the protected cross-version rollback baseline.

## Near-term priorities

1. Complete the remaining physical acceptance gates: quota direction/cutoff,
   restart and restore behavior, failure containment, interrupted setup, and
   the full factory-reset acceptance walkthrough.
2. Keep Family Captive fail-closed until its multi-instance runtime, FAS
   identity, session/accounting, nftables, and procd boundaries are separately
   implemented and field-proven.
3. Maintain release traceability: every candidate must identify its source,
   artifact checksum, target evidence, rollback point, and open gates.

## Later improvements

- Publish a user-oriented administration guide and troubleshooting index.
- Add a claim-to-evidence matrix linking features to code, tests, and field
  proof.
- Improve the visual tour with dated screenshots tied to real UI behavior.
- Separate historical release notes from current operational status.

## Status vocabulary

`Implemented` means code or documentation exists. `Tested` means an automated
or isolated check passed. `Verified` means behavior was reproduced on the
target. `Accepted` requires the complete requirement and release evidence.
Hardware-only work remains `Pending Hardware Validation` until that evidence is
recorded.
