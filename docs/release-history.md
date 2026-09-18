# Open-HotSpot release history

This ledger records the OpenWrt APK artifacts preserved in `dist/`. The
checksums are authoritative for the files in this repository. Releases r18–r35
were produced during the same implementation run; where no separate Git
commit was preserved for an individual artifact, the entry is marked as an
artifact checkpoint rather than presented as a fabricated commit history.

## Current publish checkpoint

`1.2.0-r35` is the current publish candidate. It contains the local-only FAS
path, the SQLite/domain foundation, the LuCI management pages, local portal
templates, target-specific BinAuth parsing, and the documented test evidence.
The target still has open acceptance gates for MAC reassignment policy,
management-plane isolation, counter direction, restart/session restore, and
final release freeze.

## Artifact ledger

| APK | SHA-256 | Record |
|---|---|---|
| r16 | `cfc03526e5e8c9cfe6dace0968b24ff4e63aabeab72144232196ed0ded7ad16a` | Initial preserved package and router baseline. |
| r18 | `c9f02c339c6196d3e648757ebbbcac06596d4ecc1b436d6cd9be03855e3568bb` | Preserved APK artifact; no separate release note was retained. |
| r19 | `0de0271210049248e1d8942a93fc386627bf32623f0ae1623513b6c239a5fc59` | Preserved APK artifact; no separate release note was retained. |
| r20 | `bedeb817e8f383462c083dca0e4052082150770543bbec6997d0606cf653d36a` | Preserved APK artifact; no separate release note was retained. |
| r21 | `c32c5ba5f099022ac6ba3f576e600ade3ec18b7361a129249bfa84ca954b0740` | Preserved APK artifact; no separate release note was retained. |
| r22 | `370116877d7a462903792a7885ec2f56292a32159249d5f59fae785ffc150b39` | Preserved APK artifact; no separate release note was retained. |
| r23 | `53db0bd0ff3ece80075562fc2b24e9110633b4c5874f1a237018d0f79870e62a` | Preserved APK artifact; no separate release note was retained. |
| r24 | `26a4145e8f8b7c19fb3d9fd1719f916778ced05885bfdd111e312885ba4f20c1` | Preserved APK artifact; no separate release note was retained. |
| r25 | `6323a109719290d963a3fd5b419e19cd5f1f23e6e5b8f84a5566fc6ce9e1956f` | Foundation checkpoint preserved in the artifact ledger. |
| r26 | `f94867fafad9328f7b3c6d6dfa6ab60d3e7445d695d6561174c1147ac6eba9d8` | Foundation checkpoint preserved in the artifact ledger. |
| r27 | `d0dd3887dfed4472f06ad9679f1d96bfcf03947813c4a8945c973236752a1f1a` | FAS/portal compatibility checkpoint. |
| r28 | `58fbbe7188b4e12e41389e1643b03a35b06e8800b652e689948dc13b3455a2dd` | UI/template and target validation checkpoint. |
| r29 | `127e7f260fe7319783788c89d9b9fc594ae41101ed0f3aa1173bf38bdff8a209` | SQLite busy-timeout and concurrency evidence checkpoint. |
| r30 | `7f8b0a440017add8871f7c99dcbe77f7e2c192af89b4f1c54528c1ecff652df4` | Align target `auth_client` parser with the installed seven-field contract. |
| r31 | `fcdf73813f98c76f5da6766a983b1189fe2a8ed8d3ee6cc34b950efd167e5317` | Accept Base64-encoded FAS custom data. |
| r32 | `1ae96043c06551906ed8fe2cd3866a2998d3ac4005f10bff9560b354d676d9c3` | Decode Base64 with target-available `awk` because standalone `base64` is absent. |
| r33 | `f92e84076df1add488654d5bdd4a9fa139c2e821ae9fe222f91a0f86b99c4444` | Canonicalize lowercase callback MACs before database admission. |
| r34 | `f37c1006f2757a2625e967a6ea5e466c6e0763da654ea82f736fe7fc5e85f7eb` | Add portal-template LuCI tab, empty states, and five-minute FAS handoff. |
| r35 | `9095b936e575aaf15766bc60e2bbe228f526e2ec9c3b8a3fdeaf563c3ed14856` | Current candidate; diagnostic-only trace has been removed before publish. |

## Existing GitHub history

The repository already has the semantic tags `v1.2.0` through `v1.2.3`.
The r16–r35 APK numbers are package release checkpoints, not pre-existing Git
tags. This ledger intentionally keeps those two histories distinct.
