# Building openNDS 11 for any OpenWrt architecture

The official openNDS repository provides source and an OpenWrt package
template. It does not provide one universal binary: the package must be built
with the SDK matching the target architecture.

The recorded v11 source is:

```text
Tag:       v11.0.0
Commit:    9477b224bfd6d7f27ab1f1931afb61580b9470d1
Tarball:   https://codeload.github.com/openNDS/openNDS/tar.gz/v11.0.0
SHA-256:   33940f8ef52e958cdf37fd49ca20a8140b85a096d529cf4e0122592ac24ced00
```

The source is also available from the official [openNDS repository](https://github.com/openNDS/openNDS),
and the v11 release documents the major UCI named-section change and other
security and behavior changes in its [release notes](https://github.com/openNDS/openNDS/releases/tag/v11.0.0)
and [ChangeLog](https://github.com/openNDS/openNDS/blob/11.0.00/ChangeLog).

## EA8300 build

The Linksys EA8300 uses the OpenWrt target `ipq40xx/generic` and package
architecture `arm_cortex-a7_neon-vfpv4`. Use the matching OpenWrt 25.12.x SDK,
not an `aarch64_cortex-a53` package.

From the project root:

```sh
OPENNDS_SDK=/path/to/openwrt-sdk \
OPENNDS_OUTPUT="$PWD/dist/opennds-v11" \
sh tools/build-opennds-v11.sh
```

For a complete OpenWrt 25.12.x EA8300 SDK downloaded from the OpenWrt target
SDK directory:

```sh
OPENNDS_SDK=/path/to/openwrt-sdk-ipq40xx-generic \
OPENNDS_OUTPUT="$PWD/dist/opennds-v11" \
sh tools/build-opennds-v11.sh
```

The script downloads the signed-tag source archive, verifies its SHA-256,
uses the v11 package template, builds against the supplied SDK, and copies the
architecture-specific APK/IPK to `dist/opennds-v11/` with a SHA-256 output.
The small `.build/sdk-clean` directory used by the Open-HotSpot APK packager
is not a substitute for this complete C-package SDK; it lacks the prepared
host build dependencies required by openNDS.

### Current build evidence

On 2026-09-20, the local packaging SDK was tested and correctly rejected as an
incomplete C-package SDK: the build entered host dependency preparation and
stopped at the unavailable `gperf` dependency before compiling openNDS. No v11
package was installed on the router. This is a build-environment blocker, not
evidence of an openNDS source failure.

## Other architectures

Repeat the same command with a matching SDK. The SDK determines the output
architecture; the openNDS source and package template remain the same:

```text
OpenWrt SDK for target A → opennds_11.0.0-..._<arch-A>.apk
OpenWrt SDK for target B → opennds_11.0.0-..._<arch-B>.apk
```

Do not copy the EA8300 package to another router merely because both devices
use ARM. Verify the SDK target and package architecture from the SDK metadata.

## Required validation before installation

1. Inspect the generated package architecture and dependencies.
2. Verify the target's current openNDS package and OpenWrt release.
3. Preserve the r60/openNDS 10.3.1-r3 slot as rollback.
4. Install v11 only on the disposable A/B candidate slot.
5. Validate named UCI section, FAS, custom data, BinAuth, quotas, counters,
   startup, restart, reboot, and restore behavior.
6. Do not merge v11 adapter changes into the production path until the
   [v11 contract](opennds-v11-contract.md) is fully evidenced.
