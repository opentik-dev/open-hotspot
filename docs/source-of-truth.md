# Open-HotSpot source of truth

This page is the single navigation and decision anchor for the repository.
It answers only: what is current, what is accepted, what is blocked, and where
the supporting proof lives.

## Current build anchor

The package version comes only from [`starter-kit/Makefile`](../starter-kit/Makefile):

```text
PKG_VERSION:=1.2.0
PKG_RELEASE:=112
```

The APK is built from the `starter-kit/` payload by
[`tools/build-apk.sh`](../tools/build-apk.sh). The current local artifact and
the release manifest are aligned at `1.2.0-r112` with the documented checksum.
CI must reproduce that result before publication; a CI artifact with a
different checksum is a build-environment or provenance failure, not a reason
to rewrite the manifest blindly.

## Current decision

`1.2.0-r112` is the installed controlled candidate for the EA8300 target. It
is not a production release. Hardware acceptance remains open, so no tag,
GitHub Release, or production claim is implied.

| Role | Current value |
|---|---|
| Target | Linksys EA8300 / OpenWrt 25.12.5 / `ipq40xx/generic` |
| Enforcement engine | openNDS 11.0.0 |
| Current candidate | Open-HotSpot `1.2.0-r112` |
| Immediate rollback | `r111` |
| Protected compatibility rollback | `r60` / openNDS 10.3.1-r3 |
| Release decision | Blocked by physical acceptance gates |

## Where each truth lives

| Question | Authoritative location |
|---|---|
| What must the product do? | [`specs/001-open-hotspot/spec.md`](../specs/001-open-hotspot/spec.md) and the constitution |
| What does the source implement? | `starter-kit/`, `tools/`, automated tests |
| What passed locally? | Test output and the relevant contract test |
| What happened on the router? | [`operational-ledger.md`](operational-ledger.md) and [`archive/`](archive/) |
| Can this become a release? | [`release-gates.md`](release-gates.md) and [`release-acceptance-matrix.md`](release-acceptance-matrix.md) |
| What artifact is being discussed? | [`delivery-manifest.md`](delivery-manifest.md) |
| What changed historically? | [`archive/releases/release-history.md`](archive/releases/release-history.md) and [`CHANGELOG.md`](../CHANGELOG.md) |

## Classification rule

- `Implemented` and `Tested` describe repository evidence only.
- `Verified` requires reproduction on the exact target environment.
- `Accepted` requires the requirement, automated check, and field evidence.
- `Pending Hardware Validation` remains open until target proof is recorded.
- Historical r99–r111 references stay historical unless a current page labels
  them as the active candidate or rollback checkpoint.

Do not promote a historical row, screenshot, mock, or local contract test into
current acceptance evidence.
