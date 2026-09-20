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

The v11 source archive expands to `openNDS-11.0.0` (capital `NDS`) and ships a
hand-written top-level `Makefile`. The upstream OpenWrt template does not pin
that build-directory name and still contains the legacy
`PKG_FIXUP:=autoreconf` directive. The project build helper corrects both
packaging details after verifying the template, so OpenWrt sees the source and
invokes its shipped Makefile directly. These are packaging compatibility
corrections, not source or runtime changes.

## Preparing the SDK without building unrelated packages

The OpenWrt SDK documentation describes the intended flow: update the needed
feed, install only the package feed entry required by the target package, use
`menuconfig` to select the package/dependencies, and invoke a package-specific
compile target. Do not run a bare `make` in the SDK and do not install every
feed package when preparing this build; those actions are what caused earlier
attempts to enter unrelated packages such as `unbound` and `gnutls`.

For the EA8300 SDK, the reproducible preparation is:

```sh
cd /path/to/openwrt-sdk-ipq40xx-generic
./scripts/feeds update packages
./scripts/feeds install libmicrohttpd
make menuconfig
```

In `Global build settings`, leave these three broad selections disabled:

```text
Select all target specific packages by default       [ ]
Select all kernel module packages by default         [ ]
Select all userspace packages by default              [ ]
```

Select `libmicrohttpd-no-ssl` as a module (`M`), save the configuration, and
prepare that dependency alone:

```sh
make package/libmicrohttpd/compile V=s
```

Then run the project helper from the repository root. It explicitly selects
the temporary `opennds` package as a module, cleans only its stale OpenWrt
build stamps, and invokes only that package target plus its declared
dependencies:

```sh
OPENNDS_SDK=/path/to/openwrt-sdk-ipq40xx-generic \
OPENNDS_OUTPUT="$PWD/dist/opennds-v11" \
sh tools/build-opennds-v11.sh
```

The SDK used for the recorded EA8300 build was:

```text
File:   openwrt-sdk-25.12.5-ipq40xx-generic_gcc-14.3.0_musl_eabi.Linux-x86_64.tar.zst
Size:   229319994 bytes
SHA256: af3d15643f8459335b1c98dc97dd47897d2d8e825a990a161b16b43de2281515
```

This follows the official [OpenWrt SDK workflow](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk): feed setup is explicit, broad default selections are disabled, and the final command names a package-specific compile target.

### Current build evidence

On 2026-09-20, the complete OpenWrt 25.12.5 `ipq40xx/generic` SDK compiled
openNDS 11 successfully. The generated package metadata was checked with the
SDK's APK tooling:

```text
Artifact:      dist/opennds-v11/opennds-11.0.0-r1.apk
Size:          165361 bytes
SHA256:        b43c61c0ee4530b8f1e8de8137b1ec071e3778eacd750bc140fb08d4ef8d1b1e
Architecture:  arm_cortex-a7_neon-vfpv4
Dependencies:  libc, libmicrohttpd-no-ssl
```

The earlier local packaging SDK remains documented as unsuitable for this
binary build: it stopped at the unavailable `gperf` host dependency before
compiling openNDS. No v11 package was installed on the router. The complete
target SDK above is the validated build path.

## Other architectures

Repeat the same command with a matching SDK. The SDK determines the output
architecture; the openNDS source and package template remain the same:

```text
OpenWrt SDK for target A → opennds-11.0.0-...-<arch-A>.apk
OpenWrt SDK for target B → opennds-11.0.0-...-<arch-B>.apk
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
