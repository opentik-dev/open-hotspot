# Open-HotSpot integration gap register

This is the central record for failures between services. It prevents a later
feature test or factory-reset installation from repeating a previously solved
failure. Each row must name the symptom, boundary, detection command, package
solution, and acceptance evidence.

| ID | Boundary / symptom | Root cause or decision | Package protection | Current evidence / state |
|---|---|---|---|---|
| INT-001 | Browser reaches openNDS port 2050 then `/nds/fas.php` returns 404. | Port 2050 is the openNDS return server; PHP FAS is the separate local uhttpd listener. | Local FAS uses `fasport=2080`, `faspath=/nds/fas.php`, and an explicit HTTP probe. | Fixed in r63; retest recorded in `field-evidence-20260920.md`. |
| INT-002 | Built-in Welcome/Continue page appears instead of username/PIN. | openNDS preauth/login mode overrides configured FAS. | Activation sets `login_option_enabled=0`; FAS contract test guards it. | Fixed in r61; hardware retest remains part of T003. |
| INT-003 | Changing upstream router breaks the portal. | FAS/gateway depended on a stored LAN/WAN address. | `fasremoteip` remains unset; `status.client` is used for FAS and gateway FQDN. | Fixed in r63; address-independent field proof remains open. |
| INT-004 | FAS page is absent or uhttpd serves 404. | Named uhttpd FAS instance, listener, PHP interpreter, or `/www/nds/fas.php` is missing. | Activation configures instance `open_hotspot_fas`; `diagnose.sh` checks listener and local response. | Diagnostic implemented; fresh-router proof pending. |
| INT-005 | openNDS says `Authenticated`, but manager DB remains pending. | openNDS 11 `ndscfg` can discard command-line arguments with non-tty stdin, so `custombinauth` was not loaded. | Activation sets `custombinauth`; post-install applies a recoverable UCI fallback in stock `binauth_log.sh`. | Reproduced and isolated; r66 installed; physical fresh-login proof pending. |
| INT-006 | Native session time/rate/quota output stays zero despite an account policy. | Adapter used `session_length` while stock openNDS consumes `sessiontimeout`. | Adapter maps verified native variable names and units; contract test asserts finite values. | Fixed in r66; controlled quota field proof pending. |
| INT-007 | LuCI Devices/Dashboard stays empty while openNDS has a client. | BinAuth callback did not consume `auth_transactions`, so no device/session row existed for RPC/LuCI. | Transactional `db_auth_consume` plus diagnostic warning for `Authenticated` without manager session. | Reproduced; isolated callback now creates device/session; fresh phone proof pending. |
| INT-008 | Phone appears to bypass the portal. | WARP/VPN or mobile data can create a different path, or CPD state is stale. | Acceptance runbook requires VPN/mobile-data isolation and a clean HTTP probe. | Diagnostic recorded; repeated clean test pending. |
| INT-009 | Old openNDS state survives while manager state does not, or reboot restore differs. | openNDS runtime state and manager SQLite are separate stores; restore is an explicit policy. | LuCI restore toggle, manager restore helper, and separate reboot evidence. | Enabled/disabled behavior recorded; T011 remains partial. |
| INT-010 | Client can reach LuCI/SSH/router admin ports. | Shared `br-lan` is also the management plane; portal allowance is not an admin policy. | Dedicated client/IoT network and address-independent router-access policy. | Code exists; physical isolation proof pending. |
| INT-011 | openNDS is unavailable after install/reboot. | Startup ordering, stale socket, firewall hook, or target-specific procd behavior. | Readiness recovery, bounded retries, and no upgrade-time blind restart. | Target service is running; interruption/reboot gate remains open. |
| INT-012 | Factory-reset install works once but later upgrade regresses it. | External openNDS/uhttpd files are modified without an idempotent, recoverable package step. | Post-install patch backups, idempotent UCI activation, package/install contract tests. | r65 sed regression was caught and corrected in r66; clean-install proof pending. |
| INT-013 | Root LuCI warning shows no password. | Factory OpenWrt has no admin password; this is a router security state, not a portal bug. | Runbook blocks delivery until the administrator sets a root password; package never invents credentials. | Open security acceptance item. |

## State vocabulary

`Implemented` means code or documentation exists. `Tested` means an automated
or isolated test passed. `Verified` means behavior was reproduced on the
target. `Accepted` means the requirement, test, and field evidence close the
release gate. Hardware-only rows remain `Pending Hardware Validation` until a
real client/router transcript is attached.

## Required diagnostic snapshot

On every clean install, upgrade, or boundary failure, run:

```sh
/usr/lib/open-hotspot/diagnose.sh > /tmp/open-hotspot-diagnostic.txt
```

Attach that output to the field-evidence file. It deliberately reports no FAS
key, PIN, or live credential.
