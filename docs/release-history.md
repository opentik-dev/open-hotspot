# Open-HotSpot release history

This ledger records package release checkpoints and the evidence associated
with them. Historical APK checksums refer to artifacts preserved during the
implementation run. Current releases are rebuilt from source by CI; the
release asset and its `SHA256SUMS` file are authoritative for that release.
Where no separate Git commit was preserved for an individual historical
artifact, the entry is marked as an artifact checkpoint rather than presented
as a fabricated commit history.

## Current publish checkpoint

`1.2.0-r78` is the current source/build checkpoint. r78 is the candidate for
the next CI-built release; its exact commit SHA, APK SHA-256, and acceptance
evidence must be recorded by the release workflow. Earlier packages remain
field evidence and rollback checkpoints. r40 removes upstream-address assumptions
from local FAS activation, r41 adds a dynamic-address contract guard and
rejects duplicate/overlapping LAN/WAN topology, r42 makes the preflight
directly executable, r44 discovers the LAN interface from UCI, and r45 waits
for the observed target startup window, and r46 keeps the FAS allowance
idempotent, r47 validates repeated activation with one allowance, and r48 adds
startup readiness recovery for an enabled local FAS. The target
passed the migration, RPC, PHP, backup, and isolated Renew/Reassign flow checks;
live-client acceptance gates remain open.
The target still has open acceptance gates for live-client reconnect/accounting,
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
| r36 | `8dbbf44db0e7a901f23ed8af83ae486fe4d38056e168e20d860db80a46b9c6a1` | Installed and target-validated; adds force-deauth, account-period status, and LuCI backup UI. |
| r37 | `bbae6afdfdd7568025c12cbe355047f544c62df8abec0a30bb813cc1e9bca466` | Adds audited account renewal, explicit MAC reassignment, and schema migration v4. Target validation pending. |
| r38 | `47c1da2adb5522ea35e5708895fba27e6dc990be14302f2ad48f64f1bff0eefe` | Installed and target-validated; fixes the schema-version gate so v3 databases apply migration v4 and includes Renew and MAC reassignment. |
| r39 | `89ca098440256e1624938aa8b4e7b51cee1fe28f6ee266c0f1621c8b5f7867e1` | Installed and target-validated; fixes LuCI CSRF validation to use the target's `context.authtoken` instead of `context.authsession`. |
| r40 | `52227f88316b0b8ff40c2d07453d1598ef528ef9dd4dc4e85d9fe532bf4682ae` | Removes upstream-address assumptions from local FAS activation, adds a dynamic-address contract guard, and documents Wi-Fi-upstream/Ethernet-management topology. |
| r41 | `97b5f71429d4b262f7344a163e5577429809f5610b9bb4955f501f66996a44f4` | Adds topology preflight checks for duplicate local IPs, LAN equal to the default gateway, and LAN/WAN subnet overlap. |
| r42 | `eab75827639729f1ac8f9af60d0ac410c175173ecefb190972b4421594e3dfe0` | Preserves the dynamic topology checks and fixes the package mode so `/usr/lib/open-hotspot/preflight.sh` is directly executable. Installed and base-validated on the router using its current LAN address; live-client gates remain open. |
| r43 | `e4758dc8bbf4653cc61ddd8e8ba0a14b1f10543a35b21140fef55bf75db76c0b` | Makes direct invocation of `/usr/lib/open-hotspot/preflight.sh` execute the check instead of only defining the function. |
| r44 | `8e777baff262c02fa1278ca6cd6de2d3c325fc25630deb4e05fc42f34e914241` | Discovers `gatewayinterface` from the live LAN UCI device before local-FAS activation; no IP address is embedded. |
| r45 | `f6894853bb94da77319b3e60e83f4935a009b4def1fc93742f839e7f878a5cfe` | Extends openNDS readiness to the observed cold-start window and bounds the local FAS probe. Built locally; target installation pending. |
| r46 | `5e478cf57f74e7d69f0d290e5f48a5f33e4e2e6b9890b8e248751b8ea7168bfa` | Makes the local FAS `users_to_router` allowance idempotent across repeated activation attempts. Built locally; target installation pending. |
| r47 | `50f7ddf548077993016b48929c7e59a77b25be4cf6edc9372119e358518e004b` | Fixes UCI list detection so repeated local-FAS activation retains one firewall allowance. Installed and target-validated with `ndsctl status`, dynamic FAS, topology preflight, schema v4, and RPC registration. Live-client gates remain open. |
| r48 | `5f8287b9d6b71f89bd0ca9f538726a5e6c20b4b3c0ebe93a8c66c0e33b77da6e` | Adds init-time openNDS readiness recovery when local FAS is enabled, preventing a startup respawn loop from leaving the captive path unenforced. Preserved artifact checkpoint; r49 carries the tracked post-install path. |
| r49 | `1d5a2f9a88251abec316751a5fbb916533fd65bd105dc87db8e6d6f20a1aad0f` | Makes the APK post-install script a tracked source artifact, runs the idempotent base setup on fresh installs and upgrades, and rechecks the enabled local-FAS service path. Target installation evidence is recorded; live authentication/accounting gates remain open. |
| r50 | `fe8860b11e840b40fc1bdb6d21dcedc5a4b164b38133664b48394856ee951177` | Makes explicit local-FAS activation generate a cryptographically random target-local key when a factory router has none, without printing or committing the secret. Installed and target-validated with a present 64-character key, `BASE_READY`, running openNDS, and secure local FAS. Live authentication/accounting gates remain open. |
| r51 | `f97200da0d23bbc04625972e8c6473904eb7ce6d69d41bb2cfe65ba01de35652` | Tightens the generated FAS-key allow-list to require exactly 64 hexadecimal characters. Installed and target-validated with 511 captive enforcement, working status assets, and secure local FAS. Live authentication/accounting gates remain open. |
| r52 | `062470eecf8e104de8aae1aecdad4988c63d510d2901210da0717f4bca508fff` | Adds an address-independent router-admin deny policy for a dedicated client/IoT UCI network, LuCI/RPC controls, a same-device lockout guard, and documented WARP/captive-portal acceptance tests. Built and repository-validated; isolated-network field proof remains open. |
| r53 | `4b0e48c448776001ae236d78101f30533860fe9f128649f6830dae9332390100` | Removes the upgrade-time openNDS restart race, adds bounded runtime readiness recovery with stale-socket cleanup, preserves the r52 router-access control, and records the WARP/IoT acceptance path. Target installation and live-client gates remain open until post-build validation. |
| r54 | `438e1e484a9f6df4049a4a22096554b8da6ab7f74906e15f0343fca7e3c23bc1` | Waits for an already-starting openNDS process before recovery, eliminating the S95 startup/firewall-hook restart race while retaining r53 bounded runtime recovery and r52 router-access isolation. Target installation and live-client gates remain open until validation. |
| r55 | `1460ced9a28d127b43a3902910deb6909a95692a19e8fd66ecc6538e9c97aee5` | Makes the dedicated client-network same-device/zone guards fail closed before any firewall mutation. r54’s openNDS startup/segfault finding remains an external target gate. |
| r56 | `a0ce831c17f2e959aa6f6d2ee75d230cad70587c6aa8c8a9d288d3d3e467deb9` | Adds the target-proven openNDS 10.3.1 procd stdout compatibility patch and recoverable init backup. |
| r57 | `f1a25782cca49f2a63baca43348394ca4feb0142a4e579988a3f445155b60fab` | Refines live-apk image-root detection for the stdout compatibility post-install path. |
| r58 | `9b00c3dddcb7ec164260ee1965f326294db9f08d5c09f0078abcee92a03aa34f` | Runs the compatibility patch on both fresh install and upgrade; target post-upgrade applied it and openNDS reached stable `ndsctl` readiness with preauthenticated-client rejection. |
| r59 | pending | Adds the LuCI enable/disable control and SQLite-backed, quota-aware reboot/session-process restore outside BinAuth; target validation pending. |
| r60 | CI-generated | Resolves the target's `ndsctl auth` MAC limitation by discovering the live client IP from `ndsctl status` without hardcoding any router address; enabled and disabled restore paths were validated on the EA8300. The release workflow records the exact commit SHA and artifact SHA-256. |
| r61 | pending | Forces local FAS mode 0 during activation so openNDS does not let its default ThemeSpec/PreAuth flow override the Open-HotSpot username/PIN portal; adds the explicit IoT-device exception guidance. Target retest pending. |
| r62 | pending | Explicitly enables openNDS DHCP option 114 during local-FAS activation so Android captive assistants receive the dynamic `status.client` portal URL instead of guessing the gateway address. Target retest pending. |
| r63 | pending | Corrects the openNDS 11 local-FAS contract by setting `fasremotefqdn=status.client` while leaving `fasremoteip` unset. This prevents the mode-0 `Remote Portal Not Defined`/2050-to-404 failure without storing a LAN or WAN address. Target phone retest pending. |
| r64 | pending | Connects the stock openNDS BinAuth dispatcher to the manager adapter through the `custombinauth` UCI hook and adds a recoverable UCI fallback for the target openNDS 11 `ndscfg` stdin behavior. Target fresh-login/accounting retest pending. |
| r65 | pending | Corrects the BusyBox `sed` expression in the dispatcher fallback installer. The r64 package installed but did not apply that fallback. |
| r66 | pending | Aligns the BinAuth session-duration variable with the verified openNDS contract (`sessiontimeout`), preserving native rate/quota output. Fresh-login/accounting and quota field proof remain pending. |
| r67 | pending | Packages the read-only integration diagnostic, documents the complete openNDS → uhttpd/FAS → BinAuth → SQLite → LuCI service chain and its known failure modes, and preserves r60 as the rollback baseline. Fresh physical-client proof remains pending. |
| r68 | pending | Corrects the diagnostic FAS probe to recognize the expected HTTP 400 response from a bare endpoint request, while still failing on transport or endpoint errors. Fresh physical-client proof remains pending. |
| r69 | pending | Ensures the diagnostic creates its temporary workspace before the uhttpd/FAS probe. The prior r68 field run exposed this diagnostic-only ordering defect; fresh physical-client proof remains pending. |
| r70 | pending | Preserves BusyBox wget diagnostics output so the expected HTTP 400 response from a bare FAS request is recognized; transport failures remain release failures. Fresh physical-client proof remains pending. |
| r71 | pending | Adds versioned openNDS adapter contracts for v10.3.1-r3 rollback and v11.0.0 current target; `opennds.sh` rejects unknown daemon versions. Runtime accounting, quota, restart, and failure-containment gates remain open. |
| r72 | pending | Detects and reports an active SQLite manager session with zero live openNDS clients, preventing a stale restart/close state from appearing healthy. Runtime accounting, quota, restart, and failure-containment gates remain open. |
| r73 | pending | Makes the packaged diagnostic validate the installed daemon's versioned adapter contract in addition to `ndsctl`, while retaining the explicit stale-session warning. Runtime gates remain open. |
| r74 | `9d318a81aea8038fa36d77a8e137d0635793e290032f790f39935cbb792c2da2` | Unifies the period/renewal source across FAS, BinAuth, cycle, and restore; normalizes ISO timestamps for BusyBox; applies shared SQLite timeout/foreign-key defaults; runtime gates remain open. |
| r75 | `ec19fd6470c96bd45417e3799f9d1b613f1ba65f07d9f6db0a75137331ab778f` | Adds zero-client stale manager-session reconciliation after restart/reboot; runtime gates remain open pending target evidence. |
| r76 | `12547af79c3ee5ed4927f90b1853d2e90023cdc38ddaf1f63d4d3801a6444a1e` | Expires abandoned pending FAS transactions during cycle/maintenance; runtime gates remain open pending target evidence. |
| r77 | pending | Resolves the target-specific live deauthentication path by using the current client IP from `ndsctl status` before falling back to MAC; physical close/accounting proof pending. |
| r78 | `c12a42df803b8ff50188a0849350510b0d9bb6ee71e684119d0af6a1b38ca57d` | Correlates the target openNDS 11 deauth callback's explicit base64 `empty` marker to the active MAC session so BinAuth can close and account the session without accepting unknown custom data. Physical close/accounting proof recorded; quota/restart/failure gates remain open. |
| r79 | `d443169ed707f55d6412392ce666f96f9fe44f295731466da1937d05725eb1e2` | Enables and starts the manager init service when local FAS is activated and repairs the service on live upgrade when FAS is already enabled, restoring automatic cycle/restore scheduling without mutating offline image roots. Target service/cron and automatic restore slice verified; remaining gates open. |

## Existing GitHub history

The repository already has the semantic tags `v1.2.0` through `v1.2.3`.
The r16–r51 APK numbers are package release checkpoints, not pre-existing Git
tags. This ledger intentionally keeps those two histories distinct.
