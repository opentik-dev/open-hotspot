# ADR-003: Isolated openNDS 11 migration

**Status:** Proposed — not approved for target installation  
**Date:** 2026-09-20  
**Owners:** Open-HotSpot maintainers

## Context

Open-HotSpot currently targets the verified EA8300 baseline of OpenWrt 25.12.5
with openNDS 10.3.1-r3. A major openNDS upgrade may provide security, startup,
FAS, custom-data, quota, and reauthentication improvements, but it may also
change UCI sections, callback contracts, encoded data, session timeout names,
and restore behavior.

The EA8300 must use its target package architecture:

```text
OpenWrt target:       ipq40xx/generic
Package architecture: arm_cortex-a7_neon-vfpv4
```

An `aarch64_cortex-a53` APK is not a valid substitute for this target.

## Decision

Treat openNDS 11 as a separate compatibility track, provisionally named
**Open-HotSpot 1.3 integration**. Do not replace the r60/openNDS 10 baseline
on the acceptance router until every contract in
[`opennds-v11-contract.md`](../opennds-v11-contract.md) is verified.

The existing Open-HotSpot layers remain valid in principle:

```text
LuCI / RPC
     ↓
Open-HotSpot policy + SQLite + accounting
     ├── local FAS
     ├── custom BinAuth
     └── versioned openNDS adapter
             ↓
          openNDS
```

Only the adapter contract and target integration may change. The architecture
must not be redesigned merely because the dependency version changes.

## Required investigation

Before implementation changes, verify on the exact v11 build:

- named UCI section and the canonical `faskey` path;
- FAS URL, secure level, redirect, token, and custom-data encoding;
- `auth_client` and session-close/deauthentication argument layouts;
- `sessiontimeout`, upload/download rates, and quota units;
- `ndsctl auth`/`deauth` syntax outside BinAuth;
- `custombinauth` and `binauth_log.sh` interaction;
- `auth_restore` versus manager-owned `session-restore.sh` semantics;
- startup/procd readiness and failure behavior;
- incoming/outgoing counter direction;
- IPv4/IPv6 and management-plane behavior relevant to the target.

## Validation sequence

1. Build openNDS 11 for `ipq40xx/generic` using the matching OpenWrt SDK.
2. Install it only in the disposable A/B candidate slot, preserving the r60
   recovery slot and its SSH identity.
3. Run the v11 contract tests without changing Open-HotSpot policy code.
4. Test FAS and BinAuth with a disposable account and real traffic.
5. Test openNDS restart, router reboot, restore modes, accounting, and failure
   containment separately.
6. Record evidence and update the specification/tasks only after reproduction.

## Rejected shortcuts

- Installing the A53 package on an A7 target.
- Changing `@opennds[0]` to a named path without target proof.
- Renaming callback variables without replaying real callbacks.
- Assuming v11 `auth_restore` and manager restore are interchangeable.
- Replacing the r60 baseline before a tested rollback path exists.

## Exit criteria

This ADR can move to **Accepted** only when the v11 contract, target package,
field evidence, rollback procedure, and release gates are all linked from the
project status record. Until then, v11 is research and must not be described as
the production baseline.
