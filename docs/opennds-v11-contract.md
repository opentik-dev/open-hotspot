# openNDS 11 adapter contract

This is the current v11 compatibility contract for the r74 acceptance
candidate. A row marked by the release gates as open remains a release blocker;
this document does not convert source or screenshot evidence into acceptance.

| Area | Required contract | Evidence required |
|---|---|---|
| Package | v11 build for `ipq40xx/generic` / `arm_cortex-a7_neon-vfpv4` | SDK build log and package metadata |
| UCI | Named openNDS section and canonical option paths | `uci show opennds` from target |
| FAS | URL, level, redirect, token, and secure options | Real portal capture and logs without secrets |
| Custom data | Encoding, size, and decode rules | FAS → BinAuth callback capture with redacted data |
| BinAuth | Method names, argument positions, return values | Target script/source and callback replay |
| Session policy | `sessiontimeout`, rates, upload/download quotas and units | Accepted authorization plus measured enforcement |
| Control adapter | `ndsctl auth`, `ndsctl deauth`, reload/readiness semantics | Target help/source and isolated command test |
| Accounting | Counter direction and close-event identity | Controlled upload/download and duplicate callback test |
| Restore | openNDS `auth_restore` versus manager restore ownership | Restart/reboot matrix with SQLite before/after |
| Startup | procd/init readiness, respawn, and failure behavior | Cold boot, restart, and log evidence |
| Security | FAS key handling, input validation, management isolation | Security contract tests and target retest |

## Adapter boundary

Open-HotSpot should expose stable internal operations such as:

```text
opennds_validate_config
opennds_reload
opennds_deauth <verified identity>
opennds_apply_session_policy <verified identity> <policy>
opennds_live_clients
```

Version-specific syntax belongs inside the adapter. BinAuth remains event-driven
and must not invoke `ndsctl`.

## Compatibility rule

An unresolved row is a release blocker for the v11 track. The adapter must fail
closed for new authentication when the row is required for identity or policy;
it must preserve existing authorization when a manager-side maintenance action
fails.
