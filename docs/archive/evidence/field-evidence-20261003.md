# Field evidence — r93 deployment and session-stability observation

**Date:** 2026-10-03
**Target:** Linksys EA8300, OpenWrt 25.12.5, candidate slot 02, openNDS 11.0.0
**Artifact:** `luci-app-open-hotspot-1.2.0-r93.apk`
**SHA-256:** `bd63507327ec167dc01075a71ab3d963beb77f09c9b69f797cd6818d9a11bd8a`

## Deployment evidence

- Guarded deployment upgraded `1.2.0-r92` to `1.2.0-r93`.
- SQLite export and complete rollback archive were created before mutation.
- Local and remote APK checksums matched.
- Preflight reported `topology=ok`.
- Post-install diagnostic reported `SUMMARY failures=0 warnings=0`.
- `ndsctl status` reported openNDS 11.0.0, one current client, and an
  authenticated state.
- Read-only post-install verification reported `package_version=1.2.0-r93`,
  both `events_view` and `dev_view` present, database counts
  `pending=0|active_devices=4|active_sessions=1|usage_events=61`, and one
  current authenticated client.

## Session-stability result

A second phone completed the portal login and remained connected beyond the
reported 3–4 minute eviction window. The deployment-time status showed the
same authenticated session had already been present for more than 35 minutes.
No eviction was observed during this controlled observation.

This is `Verified` evidence for the reported eviction symptom on this test
window. It does not close T006 quota mapping, T011 restart/reboot behavior, or
T086 failure-containment testing, and it does not by itself make r93 a
production baseline.

No MAC addresses, IP addresses, tokens, credentials, or backup contents are
recorded here.
