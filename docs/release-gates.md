# Open-HotSpot release-gate register

This register is the operational release decision register. `r112` is the
current installed field candidate and contains the openNDS 11 service-plane
lookup correction; its guarded post-install health validation passed. `r111` is
the immediate rollback checkpoint and `r60` remains the protected cross-version
rollback baseline. r99 and r100 remain historical candidate/rollback records.
The current candidate is not a production release until the physical gates
below have evidence.
Neither is a production release
until every critical gate below has evidence from the physical target.

| Priority | Risk / failure mode | Likelihood | Impact | Required closure evidence | Owner | Status |
|---|---|---:|---:|---|---|---|
| Critical | Portal/FAS succeeds but BinAuth does not create the manager session or accounting record. | Medium | High | Disposable client completes portal → FAS → openNDS → BinAuth → active session → close callback; SQLite shows one consumed transaction, one session, and one usage event. | Engineering + field validation | Verified on r78 primary physical path; duplicate callback remains covered by automated idempotency tests |
| Critical | Upload/download counters are reversed or native quota cutoff is not enforced. | Medium | High | Controlled upload/download test maps both counters and records the measured cutoff bound for time and bytes. | Engineering + field validation | Open — T006; r90 adds target callback-name compatibility after the first download cutoff exposed INT-030 |
| Critical | Router/openNDS restart duplicates usage or loses the live-session policy. | Medium | High | Separate openNDS restart and router reboot tests, with before/after session and usage queries. | Engineering + field validation | Partial — r88 contains native openNDS restore containment when manager restore is disabled; r89 fixes the pre-auth callback bridge; full live-session/dedup matrix remains open (T011/E-013) |
| High | Manager, BinAuth, or cycle failure disconnects existing clients or permits unsafe new authentication. | Medium | High | Inject each failure while a client is connected: existing authorization remains unchanged; new identity decisions fail closed; failure is logged. | Engineering | Open — T086 |
| High | Interrupted setup leaves partial configuration or an unhealthy service. | Medium | High | Interrupt setup at each state, rerun it, verify rollback/recovery, dependency health, and service readiness. | Engineering | Open — T052/T087 |
| High | LuCI/RPC management surface is reachable from the client or captive-portal plane. | Low | High | From a client network, management ports and RPC are unreachable; from the admin plane, authenticated LuCI works. | Network/operations | Open — field test |
| High | A device MAC is silently attributed to another account or cannot be safely reassigned. | Low | High | Controlled policy test: same MAC switches only after the previous account is inactive/expired/deleted/exhausted, no live/pending session exists, the target snapshot is current, and a redacted audit event is written; administrative reassignment remains explicit. | Engineering | Implemented — isolated source proof; target/client proof open |
| Medium | Renewal could discard history or leave active devices on stale policy. | Medium | High | `account_renew` records `renewed_at`, preserves prior aggregates, deauthenticates active devices, and starts a fresh effective window. | Engineering | Implemented — isolated target proof; reconnect proof open |
| Medium | Backup import is accepted but recovery is not proven on the target. | Low | High | Export, validate, import into a disposable state, verify rollback archive, and confirm accounts/profiles/history after reload. | Engineering + field validation | Partially closed — archive structure, SQLite integrity/schema, and target-side validation passed; target import/rollback and post-reload proof remain open |
| High | A/B slot rollback is mistaken for shared application state or SSH identity. | Medium | High | Switch 02 → 01 → 02 through Advanced Reboot using the currently discovered management address; verify separate host-key files, admin keys, firmware identity, and explicit backup/import boundaries. | Network/operations | Open — runbook added |
| High | FAS keeps a stale upstream/WAN address after the Internet source changes. | Medium | High | `fasremoteip` remains unset, `fasremotefqdn=gatewayfqdn=status.client`, and a client on Open-HotSpot `br-lan` completes the portal after changing upstream connectivity. | Engineering + field validation | Verified on r78 through direct Ethernet portal flow; full external-internet/changed-upstream retest remains open |
| High | Two routers expose the same LAN address/subnet, causing duplicate gateways or a broken laptop route. | High | High | Preflight rejects duplicate local IPs, LAN equal to the default gateway, and LAN/WAN subnet overlap; field setup uses two discovered, non-overlapping networks. | Engineering + network validation | Code guard in r48 — field topology proof open |
| Critical | openNDS exits with `exit_code=139` during startup and leaves `ndsctl` busy/unavailable. | Medium | High | Identify and correct the target openNDS/OpenWrt binary/runtime fault, then prove stable `ndsctl`, portal 511/FAS redirect, and restart recovery. | Platform/network validation | Resolved on r58 startup and reboot — service/captive-session gates remain open (E-011/E-012) |
| High | dnsmasq lacks nftset support required by a selected openNDS walled-garden/blocklist feature. | Medium | Medium | Run the packaged capability gate; if selected, install target-feed `dnsmasq-full`, then verify `dnsmasq --test`, DHCP, and the selected openNDS feature. | Platform/network validation | Conditional capability gate implemented; target has `dnsmasq-full`/`nftset`; autonomous feature proof open |
| High | Wi-Fi disappears while portal/application services remain healthy. | Medium | High | Preflight rejects malformed `/etc/board.json`; explicit recovery regenerates and validates it, then `wifi status` shows AP interfaces enabled and the phone sees the SSID. | Platform/network validation | Router-side repair Verified; phone visibility and portal flow open |
| Critical | A VPN/WARP tunnel is retained or established before captive authentication, making a phone appear to bypass the portal. | Medium | High | Force-stop VPN, clear Wi-Fi state, verify `Preauthenticated` → login → `Authenticated`, then repeat with VPN before and after login and after service/router restart. | Engineering + field validation | Diagnostic recorded in E-008 — clean retest open |
| High | Clients can reach router administration through openNDS essential ports. | Medium | High | Put an IoT SSID/VLAN on a separate UCI device, apply r52 deny policy, prove ports 22/80/443 fail while portal ports work; prove admin plane remains reachable. | Network/operations | Code in r52 — isolated-network proof open |
| Release stop | Baseline is frozen while any blocking gate remains open. | Certain | High | T090 is checked only after T003/T006/T011/T012/T052/T086–T088 and the Renew/MAC decisions are evidenced. | Release owner | Open — no-go |

## Current decision

`r60` remains the protected rollback baseline. `r111` is the immediate rollback
checkpoint, while `r112` is the current installed controlled candidate.
Hardware validation remains pending, and r112 is not approved as a production
baseline. The next field session
must prioritize the disposable client flow, counter/quota mapping, and restart
behavior; code changes must not claim those gates closed without target evidence.

The dual-boot layout reduces recovery risk, but it does not make the two
partitions a shared data store and does not close T011 by itself. A partition
switch is a reboot event and must be recorded with the slot-specific SSH host
key and administrator key.

The delivery artifact, packaged diagnostic, and exact factory-reset acceptance procedure are
recorded in [`delivery-manifest.md`](delivery-manifest.md) and
[`factory-reset-acceptance-runbook.md`](factory-reset-acceptance-runbook.md).

## 2026-10-02 audit note

The current target preflight passes, but a read-only audit found stale
`PREFLIGHT_FAILED` UCI state and recurring `session_reconcile_failed` and
`policy_refresh_failed` events. Raw logs also contain dnsmasq reload and
preemptive-MAC failures. These findings keep the runtime and failure-containment
gates open; the packaged diagnostic's zero summary is not sufficient to close
them. The observed authenticated client did not disconnect during a controlled
4-minute observation, so the reported 3–4 minute eviction still requires a
reproducible account-specific field trace.
The partial A/B execution, including the SCP/SFTP and SSH-access failures, is
recorded in [`field-evidence-20260918.md`](field-evidence-20260918.md).
