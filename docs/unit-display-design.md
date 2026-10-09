# Human-friendly quota and rate units

This is the approved follow-up design for r91. It is intentionally separate
from the r90 migration and does not change the database schema or openNDS
adapter contract.

## Canonical storage

- time: integer seconds;
- traffic quotas: integer bytes;
- rates: integer kbit/s, matching the verified openNDS contract.

The LuCI form will accept an integer value plus a unit selector and convert at
the RPC boundary. Existing RPC and CLI field names remain valid for backward
compatibility, so API clients and backups do not change.

## User-facing selectors

- time: seconds, minutes, hours, days, weeks;
- data: B, KiB, MiB, GiB;
- rate: bit/s, kbit/s, Mbit/s, Gbit/s.

Binary units are labelled `KiB/MiB/GiB` to avoid silently confusing 1000 and
1024. Rates use decimal SI multipliers and are normalized to integer kbit/s;
values that cannot be represented safely are rejected with a validation error.
Zero remains the existing unlimited value.

## Acceptance requirements

Add unit-conversion contract tests for create and update forms, overflow and
zero/unlimited behavior, and round-trip display. Keep the canonical values in
the database and ensure the FAS/BinAuth/quota tests still see seconds, bytes,
and kbit/s. Ship the UI conversion as a new release after the r90 physical
baseline, not as an untracked mutation of the r90 pilot.
