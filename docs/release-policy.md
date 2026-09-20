# Release and version policy

The package version is the pair declared in `starter-kit/Makefile`:

```text
PKG_VERSION:=1.2.0
PKG_RELEASE:=63
```

The installable artifact is named:

```text
luci-app-open-hotspot-${PKG_VERSION}-r${PKG_RELEASE}.apk
```

## Rules

1. Every release change updates `PKG_RELEASE` monotonically. A change to the
   product line or incompatible schema changes `PKG_VERSION`.
2. A release tag is exactly `v${PKG_VERSION}-r${PKG_RELEASE}`; for example,
`v1.2.0-r63`.
3. Tags are created only from a commit that passed CI. The release workflow
   rebuilds the APK from source and never publishes a committed APK as the
   build input.
4. The release workflow checks `tools/check-release-gates.sh`; T003, T006, T011,
   T012, T052, T086, T087, T088, and T090 must be checked off in `tasks.md`.
   An open physical-acceptance gate makes the release fail.
5. The release body links the exact commit SHA, APK SHA-256, acceptance matrix,
   delivery manifest, and all open release gates.
6. A release is not production-approved while a Critical or Release-stop gate
   is open in `docs/release-gates.md`.
7. Target-specific compatibility patches must name the OpenWrt/openNDS build,
   preserve a rollback artifact, and include field evidence before the gate is
   closed.

## Release sequence

```text
feature branch → PR → CI checks/build → review → merge to main
→ update release metadata → tag vX.Y.Z-rN → CI rebuilds APK
→ acceptance matrix review → GitHub Release
```

The release workflow requires the tag to match `starter-kit/Makefile`. If it
does not, publishing stops.
