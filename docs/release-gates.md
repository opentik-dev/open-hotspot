# Open-HotSpot release-gate register

This register is the operational release decision for `luci-app-open-hotspot
1.2.0-r70`. r70 is the current candidate with router-access isolation,
runtime readiness recovery, and a packaged read-only integration diagnostic;
it
is not a production release until every critical
gate below has evidence from the physical target.

| Priority | Risk / failure mode | Likelihood | Impact | Required closure evidence | Owner | Status |
|---|---|---:|---:|---|---|---|
| Critical | Portal/FAS succeeds but BinAuth does not create the manager session or accounting record. | Medium | High | Disposable client completes portal → FAS → openNDS → BinAuth → active session → close callback; SQLite shows one consumed transaction, one session, and one usage event. | Engineering + field validation | Code corrected in r66 and diagnosed by r70 — fresh-client proof open |
| Critical | Upload/download counters are reversed or native quota cutoff is not enforced. | Medium | High | Controlled upload/download test maps both counters and records the measured cutoff bound for time and bytes. | Engineering + field validation | Open — T006 |
| Critical | Router/openNDS restart duplicates usage or loses the live-session policy. | Medium | High | Separate openNDS restart and router reboot tests, with before/after session and usage queries. | Engineering + field validation | Partial — enabled/disabled reboot restore proven; restart accounting and usage-deduplication remain open (T011/E-013) |
| High | Manager, BinAuth, or cycle failure disconnects existing clients or permits unsafe new authentication. | Medium | High | Inject each failure while a client is connected: existing authorization remains unchanged; new identity decisions fail closed; failure is logged. | Engineering | Open — T086 |
| High | Interrupted setup leaves partial configuration or an unhealthy service. | Medium | High | Interrupt setup at each state, rerun it, verify rollback/recovery, dependency health, and service readiness. | Engineering | Open — T052/T087 |
| High | LuCI/RPC management surface is reachable from the client or captive-portal plane. | Low | High | From a client network, management ports and RPC are unreachable; from the admin plane, authenticated LuCI works. | Network/operations | Open — field test |
| High | A device MAC is silently attributed to another account or cannot be safely reassigned. | Low | High | Explicit policy test: same MAC under another account is rejected; reassignment requires no live session, an active target account, and an audit event. | Engineering | Implemented — isolated target proof; live-client proof open |
| Medium | Renewal could discard history or leave active devices on stale policy. | Medium | High | `account_renew` records `renewed_at`, preserves prior aggregates, deauthenticates active devices, and starts a fresh effective window. | Engineering | Implemented — isolated target proof; reconnect proof open |
| Medium | Backup import is accepted but recovery is not proven on the target. | Low | High | Export, validate, import into a disposable state, verify rollback archive, and confirm accounts/profiles/history after reload. | Engineering + field validation | Partially closed — r38 helper validated; restore flow open |
| High | A/B slot rollback is mistaken for shared application state or SSH identity. | Medium | High | Switch 02 → 01 → 02 through Advanced Reboot using the currently discovered management address; verify separate host-key files, admin keys, firmware identity, and explicit backup/import boundaries. | Network/operations | Open — runbook added |
| High | FAS keeps a stale upstream/WAN address after the Internet source changes. | Medium | High | `fasremoteip` remains unset, `fasremotefqdn=gatewayfqdn=status.client`, and a client on Open-HotSpot `br-lan` completes the portal after changing upstream connectivity. | Engineering + field validation | Code guard in r63 — client proof open |
| High | Two routers expose the same LAN address/subnet, causing duplicate gateways or a broken laptop route. | High | High | Preflight rejects duplicate local IPs, LAN equal to the default gateway, and LAN/WAN subnet overlap; field setup uses two discovered, non-overlapping networks. | Engineering + network validation | Code guard in r48 — field topology proof open |
| Critical | openNDS exits with `exit_code=139` during startup and leaves `ndsctl` busy/unavailable. | Medium | High | Identify and correct the target openNDS/OpenWrt binary/runtime fault, then prove stable `ndsctl`, portal 511/FAS redirect, and restart recovery. | Platform/network validation | Resolved on r58 startup and reboot — service/captive-session gates remain open (E-011/E-012) |
| High | dnsmasq lacks nftset support required by a selected openNDS walled-garden/blocklist feature. | Medium | Medium | Install the target-feed `dnsmasq-full` replacement with config hashes preserved, then verify `dnsmasq --test`, DHCP, and the selected openNDS feature. | Platform/network validation | Capability installed on target — feature/runtime proof open (E-010) |
| Critical | A VPN/WARP tunnel is retained or established before captive authentication, making a phone appear to bypass the portal. | Medium | High | Force-stop VPN, clear Wi-Fi state, verify `Preauthenticated` → login → `Authenticated`, then repeat with VPN before and after login and after service/router restart. | Engineering + field validation | Diagnostic recorded in E-008 — clean retest open |
| High | Clients can reach router administration through openNDS essential ports. | Medium | High | Put an IoT SSID/VLAN on a separate UCI device, apply r52 deny policy, prove ports 22/80/443 fail while portal ports work; prove admin plane remains reachable. | Network/operations | Code in r52 — isolated-network proof open |
| Release stop | Baseline is frozen while any blocking gate remains open. | Certain | High | T090 is checked only after T003/T006/T011/T012/T052/T086–T088 and the Renew/MAC decisions are evidenced. | Release owner | Open — no-go |

## Current decision

`r70` is suitable for controlled pilot validation and rollback testing. It is
not approved as a production baseline. The next field session must prioritize
the disposable client flow, counter/quota mapping, and restart behavior; code
changes must not claim those gates closed without target evidence.

The dual-boot layout reduces recovery risk, but it does not make the two
partitions a shared data store and does not close T011 by itself. A partition
switch is a reboot event and must be recorded with the slot-specific SSH host
key and administrator key.

The delivery artifact, packaged diagnostic, and exact factory-reset acceptance procedure are
recorded in [`delivery-manifest.md`](delivery-manifest.md) and
[`factory-reset-acceptance-runbook.md`](factory-reset-acceptance-runbook.md).
The partial A/B execution, including the SCP/SFTP and SSH-access failures, is
recorded in [`field-evidence-20260918.md`](field-evidence-20260918.md).
