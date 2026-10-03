# Operational ledger schema

Each entry must contain:

| Field | Requirement |
|---|---|
| ID | Monotonic `OP-NNN` identifier. |
| Date | ISO date in the operator's timezone. |
| Operation | Short action name and release/gate context. |
| Target state | Slot, platform, and discovered capabilities; omit secrets and raw client identifiers. |
| Attempt | Command path or action, summarized without credentials. |
| Result | `success`, `failure`, or `partial`. |
| Classification | `environment`, `contract`, `implementation`, or `evidence`. |
| Reuse rule | The exact path to use or avoid next time. |
| Evidence | Test output, screenshot reference, checksum, or sanitized observation. |
| Gate status | `Implemented`, `Tested`, `Verified`, `Accepted`, or `Pending Hardware Validation`. |

For a failure, explain the changed variable required before another attempt.
Do not turn a failure into a success by changing its wording after the fact.
