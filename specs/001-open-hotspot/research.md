# Phase 0 Research — Open-HotSpot v1.2 Architecture-Corrected

## 1. Purpose

This document records facts that must be established before implementation can
be treated as an implementation baseline. The project deliberately separates
**documented behavior**, **design decisions**, and **target-build verification**.

The most important correction from v1.1 is:

> **BinAuth must never invoke `ndsctl`.**

BinAuth is an openNDS callback context. Administrative `ndsctl` operations, if
needed, belong to LuCI/backend/maintenance processes outside that callback.

## 2. Verified Architectural Facts from openNDS Documentation/Source History

### 2.1 Native enforcement exists
openNDS supports session length, upload/download rate limits, and upload/download
volume quotas. These can be supplied through supported authentication/FAS/BinAuth
mechanisms depending on the build and integration path.

**Design consequence:** Open-HotSpot must calculate policy but delegate traffic
enforcement to openNDS rather than implementing its own packet/byte collector.

### 2.2 BinAuth is event-driven
openNDS invokes BinAuth with a method-specific reason and a target-build
argument layout. The resolved target v10.3.1 script has two layouts:
`auth_client` receives MAC, origin URL, user agent, client IP, token, and
custom data; other reasons receive MAC, incoming/outgoing counters, session
start/end, token, and custom data.

**Design consequence:** each method branch must have its own parser and Phase 0
must capture the exact contract for the resolved build.

### 2.3 `ndsctl` inside BinAuth is prohibited
openNDS has historically included protection against running `ndsctl` from a
BinAuth context because the two execution paths can contend on the same control
state/lock.

**Design consequence:** this is an architectural prohibition, not merely a
performance recommendation. `binauth.sh` must contain no `ndsctl` invocation.

### 2.4 FAS is the natural credential-verification boundary
The local FAS path can receive the portal login, verify credentials locally,
and hand an authenticated client back into openNDS through its documented FAS
contract. FAS also supports passing policy-related values such as session/rate/
volume parameters on supported levels.

**Design consequence:** the PIN is verified before openNDS authorization, and the
manager passes an account/policy context rather than asking BinAuth to discover
an account from a MAC address.

## 3. Target-Build Gates

The following gates are mandatory against the exact openNDS package installed
or selected for the target OpenWrt architecture.

### GATE A — BinAuth contract
Record:

- exact openNDS version/package revision
- `auth_client` arguments and return semantics
- all deauth/session-close method names
- exact argument positions for MAC, counters, session start/end, token/custom data
- whether values are bytes, kB, seconds, minutes, or another unit

**Status: CLOSED for the resolved target contract; end-to-end callback remains
part of T012.**

### GATE B — FAS authentication handoff
Record:

- local FAS URL/path
- exact authentication endpoint/redirect format
- exact custom-variable parameter name
- secure FAS level available on target
- how `rhid`/token/custom values are preserved
- whether the returned policy values are accepted directly by openNDS

**Status: OPEN until verified on target.**

### GATE C — Native quota return path
The project needs one verified path for:

```text
verified account
      ↓
policy calculation
      ↓
openNDS session/rate/volume ceilings
```

The implementation may use FAS-returned parameters, a documented BinAuth return
mechanism, or another native mechanism **only if the target build proves it**.

**Status: OPEN until verified on target.**

### GATE D — `ndsctl` outside BinAuth
If period rollover, force-deauth, or policy refresh requires `ndsctl`, verify:

- exact `ndsctl auth` syntax and argument order
- exact units
- exact `ndsctl deauth` syntax
- whether the command is safe from LuCI/backend/cron context

No production code is written against guessed syntax.

**Status: OPEN until verified on target.**

### GATE E — Counter mapping
Determine which openNDS counters correspond to upload/download from the
manager's perspective. Preserve both raw fields until this is experimentally
verified.

**Status: OPEN until verified on target.**

### GATE F — Local FAS runtime
Verify the target supports the selected local FAS implementation and its
runtime dependencies without introducing an unnecessary PHP/web stack.

**Status: OPEN until verified on target.**

### GATE G — Password KDF
Verify that the selected OpenWrt crypto package actually exposes a suitable
PBKDF2 implementation. Do not use `mkpasswd -m sha256` as if it were PBKDF2.
If PBKDF2 is unavailable, setup must stop rather than silently downgrade the
credential scheme.

**Status: OPEN until verified on target.**

### GATE H — dnsmasq-full requirement
Verify whether the selected openNDS feature set requires `dnsmasq-full`. It is
not a universal Open-HotSpot dependency.

**Status: OPEN until verified for selected features.**

### GATE I — Restart/auth-restore behavior
Test reboot and openNDS restart separately. SQLite usage persistence is required,
but persistence of live openNDS sessions is a separate claim and must be verified.

**Status: OPEN until tested.**

## 4. Identity Model Decision

The account is the identity. MAC is a device attribute.

```text
portal credentials
      ↓
verified Account
      ↓
authorization context
      ↓
Device(MAC) associated with Account
```

A MAC must never be accepted as proof of account identity.

## 5. Authentication Architecture Decision

The corrected flow is:

```text
Client
  ↓
openNDS portal
  ↓ POST username + PIN
local FAS/login handler
  ↓
SQLite credential verification
  ↓
create short-lived auth_transaction
  ↓
verified openNDS authorization handoff
  ↓
openNDS
  ↓
BinAuth callback
  ├─ consume/validate the handoff context
  ├─ establish/confirm device + live-session state
  └─ on session close: accounting only
```

The exact handoff field and exact place where session/rate/volume ceilings are
returned are **Phase 0 gates**, not invented here.

## 6. Authorization vs Accounting

### Authorization path
Responsible for:

- credential verification
- account status/expiry
- profile resolution
- current aggregate budget
- simultaneous-device decision
- supplying native openNDS session policy

### BinAuth path
Responsible for:

- receiving the documented callback
- consuming/validating the short-lived authorization context where required
- maintaining live-session state
- recording session-close/deauth counters
- idempotent usage aggregation

### Maintenance path
Responsible for:

- period rollover
- hard expiry sweep
- retention/WAL maintenance
- policy refresh/deauth only through verified commands outside BinAuth

## 7. Quota Semantics

Time/data budgets are account-level aggregate budgets within a period.

Example:

```text
Profile: 2 hours / 500 MB / daily
Phone:   70 min + 200 MB
Laptop:  30 min + 100 MB
----------------------------
Account: 100 min + 300 MB used
Remaining: 20 min + 200 MB
```

A rate limit is not added to the period usage total; it is a per-session native
ceiling.

## 8. Period-Spanning Sessions

A session from 23:59 to 00:30 cannot be charged entirely to either side of the
boundary. The accounting implementation must split the interval/counters or
use a verified equivalent that produces the same per-period totals.

This is a correctness requirement, not an optimization.

## 9. SQLite Decision

SQLite is appropriate for a single-router manager because the workload is small,
local, transactional, and event-oriented. WAL plus explicit transactions gives
safe concurrent writes for the voucher and accounting races.

The shell database wrapper does **not** claim prepared-statement binding. It uses
strict allow-lists for identifiers and correct SQL escaping for permitted text
values. A compiled binding helper may be added later, but it is not required by
v1.2 if every untrusted field is correctly constrained.

## 10. Password Storage Decision

Required:

```text
random salt + PBKDF2-HMAC-SHA256 + benchmarked iteration count
```

Not acceptable:

```text
sha256(PIN)
sha256(PIN + salt) once
mkpasswd sha256 presented as PBKDF2
plaintext PIN
```

If the target package cannot provide the selected KDF, setup fails closed.

## 11. dnsmasq-full Decision

`dnsmasq-full` is feature-dependent. Open-HotSpot should not replace a working
base dnsmasq solely because a template or basic openNDS deployment does not need
full dnsmasq functionality.

If a future feature requires it, the setup state machine must stage, verify,
replace, and health-check the DNS/DHCP service before completion.

## 12. Failure Model

```text
NEW AUTH + manager unavailable
        → deny/abort

EXISTING OPENNDS SESSION + manager unavailable
        → preserve last openNDS state
```

This avoids both dangerous fail-open authentication and unnecessary disruption
of already-authorized clients.

## 13. Phase 0 PoC

Before Phase 1/2 production implementation, build a disposable proof of concept
that demonstrates, on the target router:

1. local portal receives username + PIN
2. PIN verification succeeds/fails correctly
3. verified identity reaches the supported openNDS authorization path
4. one session receives a known short time/data/rate policy
5. openNDS enforces it
6. BinAuth receives the expected callback arguments
7. session close produces one accounting event
8. repeating the callback does not double-count
9. a session spanning a period boundary can be accounted correctly
10. manager/BinAuth failure does not intentionally revoke an existing session

The PoC is the exit criterion for GATEs A–I where applicable.

## 14. Research Deliverables

`quickstart.md` must record the actual commands, versions, outputs, and observed
results used to close each gate. The production plan must reference those
results rather than repeating undocumented assumptions.

## 15. Target Build Evidence — 2026-09-16

The first target verification was performed against the reachable Ethernet
router at `192.168.70.1`. No configuration was changed by the verification.

### 15.1 Target identity

```text
Model:          Linksys EA8300 (Dallas)
Board:          linksys,ea8300
OpenWrt:        25.12.5 r33051-f5dae5ece4
Target:         ipq40xx/generic
Architecture:   arm_cortex-a7_neon-vfpv4 / ARMv7
openNDS:        10.3.1-r3
SQLite CLI:     3.53.1
PHP:            8.4.21 CGI
```

The stable online documentation currently identifies itself as openNDS v10.3.0;
the installed v10.3.1 package and matching upstream v10.3.1 source were used
where the patch-level contract differs.

### 15.2 BinAuth contract — Gate A

The installed sample and the official BinAuth documentation agree on these
method names:

```text
auth_client, client_auth, client_deauth, idle_deauth,
timeout_deauth, downquota_deauth, upquota_deauth,
ndsctl_auth, ndsctl_deauth, shutdown_deauth
```

The stable documentation still describes the deprecated `auth_client` form
with username/password positions. The installed target script uses distinct
layouts:

```text
$1 method/reason
$2 client_mac
$3 originurl             # auth_client only
$4 useragent             # auth_client only
$5 clientip              # auth_client only
$6 client_token          # auth_client only
$7 url-escaped custom    # auth_client only

$3 bytes_incoming        # all other callback reasons
$4 bytes_outgoing
$5 session_start
$6 session_end
$7 client_token
$8 url-escaped custom
```

The adapter rejects the older username/password layout rather than trying to
infer which contract a callback used.

The custom variable is not a username field. It is a URL-escaped opaque value
provided by the FAS. The implementation must use the token/session context and
must not infer an account from the MAC alone. The default target BinAuth
script's final contract is: stdout contains five numeric values
`session_length upload_rate download_rate upload_quota download_quota`, and
exit status 0 allows authentication while exit status 1 denies it.

Evidence: installed `/usr/lib/opennds/binauth_log.sh`, installed
`/usr/lib/opennds/custombinauth.sh`, `ndsctl` help, the target v10.3.1
`auth.c` source, and the official
[BinAuth documentation](https://opennds.readthedocs.io/en/stable/binauth.html).

### 15.3 FAS and native quota contract — Gates B/C (pre-activation snapshot)

The live router currently has:

```text
fasremoteip=192.168.70.1
fasremotefqdn=portal.opentikno.win
fasport=443
faspath=/fas/login.php
fas_secure_enabled=4
```

This is a remote HTTPS FAS/Authmon deployment, not the local FAS path planned
for the manager. At the time of this pre-activation snapshot the router's WAN
interface was down and had only the
LAN route, so a direct `uclient-fetch` probe to the FAS failed with status 4
after approximately 5 seconds. After WAN was connected, the lease became
`192.168.50.156/24` via `192.168.50.1`; those entries remain historical
evidence rather than the current state.

For secure level 4, the verified Authmon return fields are:

```text
rhid
sessionlength  (minutes)
uploadrate     (kbits/sec)
downloadrate  (kbits/sec)
uploadquota    (kBytes)
downloadquota (kBytes)
custom         (sent to BinAuth)
```

The official documentation states that secure levels 3 and 4 use HTTPS and
Authmon, and that level 4 is intended for a remote FAS. A local FAS on this
router therefore needs a separate verified design, likely level 1/2 with the
corresponding security and PHP requirements; it must not be implemented by
changing the current level-4 values by guesswork.

Evidence: live UCI configuration, installed `/usr/lib/opennds/authmon.sh`,
installed `/etc/opennds/fas-hid-https.php`, and the official
[FAS documentation](https://opennds.readthedocs.io/en/stable/fas.html).

### 15.4 `ndsctl` contract — Gate D

The target reports the exact supported administrative interface:

```text
ndsctl auth mac|ip|token sessiontimeout(minutes) uploadrate(kb/s)
             downloadrate(kb/s) uploadquota(kB) downloadquota(kB) customstring
ndsctl deauth mac|ip|token
```

The target help and official documentation agree on these units. `ndsctl`
operations are not persistent across an openNDS restart. No authentication or
deauthentication command was issued during verification.

### 15.5 Counters — Gate E

The official semantics confirm that upload means traffic from the client to the
Internet and download means traffic from the Internet to the client. BinAuth
provides `bytes_incoming` and `bytes_outgoing`. A controlled client traffic
experiment is still required to confirm the router's counter direction before
the project maps those fields into aggregate upload/download totals.

### 15.6 Runtime and KDF — Gates F/G

The target has `php8-cgi`, `php8`, `php8-mod-pdo`, and
`php8-mod-pdo-sqlite`. It does not have the `openssl` CLI or the PHP OpenSSL
module. The PHP `hash` extension does provide `hash_pbkdf2`; a non-secret test
call returned a 64-character SHA-256 PBKDF2 hex result. The target does not
provide PHP `ctype` or the `od` utility, so the project adapter uses PHP core
regex validation, `hexdump` for the salt, and the verified PHP KDF path over
stdin. It fails closed if the helper or PHP CGI binary is unavailable and does
not downgrade to SHA-256-crypt.

The selected default is 100,000 iterations. On the target router, the measured
wall times were approximately 1.10 seconds at 50,000 iterations, 2.19 seconds
at 100,000, and 3.06 seconds at 150,000. A complete hash/verify test on the
target accepted the correct PIN and rejected an incorrect PIN.

### 15.7 dnsmasq — Gate H

The target has `dnsmasq`, not `dnsmasq-full`. openNDS starts and serves its
portal, but its startup log reports that walledgarden and blocklist setup cannot
be configured because the nftset/ipset compile options are missing. This makes
`dnsmasq-full` a conditional dependency for those features, not a core
dependency for the manager's SQLite, FAS, or native quota path.

### 15.8 Restart and startup timing — Gate I

The target has no active clients during the test.

Full router reboot observation:

```text
First openNDS start attempt: 22:21:22
br-lan not ready / first process exits: 22:21:43
Second start attempt: 22:21:53
br-lan receives 192.168.70.1: 22:22:02
MHD server created: 22:22:03
openNDS is now running: 22:22:08
```

The successful openNDS attempt took about 15 seconds from process startup to
running. The first attempt added about 31 seconds because `br-lan` was not yet
ready. SSH returned during the router recovery polling at roughly 80 seconds;
the first usable `ndsctl status` response followed shortly after, with transient
`ndsctl` busy responses during startup.

The service restart test exposed an operational issue: `/etc/init.d/opennds
restart` returns in about 1 second, but the old process exits later and procd
respawns openNDS. During the test, `ndsctl` reported the stale status for a few
seconds, then connection refused, and the new process reached `openNDS is now
running` about 30 seconds after the exit. The service eventually returned to
`running`, but the command return time is not the readiness time.

The current configuration points `option binauth` to a replacement
`custombinauth.sh`. The official documentation warns that replacing the
default BinAuth script disables the default `auth_restore` functionality. Live
session restoration after reboot was not claimed because no authenticated
client was available; this remains an open acceptance test.

### 15.9 Gate status after target verification

```text
T001  CLOSED — exact target/package identified
T002  CLOSED for contract capture — live callback still belongs to T012
T003  OPEN — local FAS response is proven, but live openNDS authorization is not proven
T004  CLOSED for documented native path — end-to-end enforcement still T012
T005  CLOSED — exact ndsctl syntax and units captured
T006  OPEN — controlled upload/download experiment pending
T007  CLOSED — target PHP/PDO/KDF dependencies and live local uhttpd flow verified
T008  CLOSED — PHP hash_pbkdf2 exists and the project adapter uses it
T009  CLOSED — 100,000 iterations selected; target benchmark recorded below
T010  CLOSED conditionally — dnsmasq-full only for walledgarden/blocklist
T011  OPEN — live-session restore not tested
T012  OPEN — a disposable client session is still required for portal → FAS → openNDS → BinAuth → accounting
T013  CLOSED for callback contract — no `ndsctl` call and accounting-failure
      preservation are covered; live-client behavior remains part of T012
```

### 15.10 Local FAS implementation boundary — official-doc reduction

The official FAS guide reduces the local design choices without requiring a
matrix test of every security level:

* level 1 is the selected local path because it uses the documented HID/token
  handoff and does not require the target's missing PHP OpenSSL module;
* levels 2 and 3 are not selected because the guide requires PHP OpenSSL for
  those levels and the target does not provide it;
* level 4 is not selected for this local-only deployment because the guide's
  example is an HTTPS/Authmon FAS that cannot be hosted on the private router;
* the FAS PHP endpoint must use a second uhttpd HTTP port (planned `2080`),
  because openNDS reserves port 80 for the captive portal.

The implementation at `starter-kit/root/www/nds/fas.php` follows the level-1
contract: it verifies the account/PIN locally, creates a two-minute opaque
`auth_transactions` record, and returns the documented `tok`, `custom`, and
`redir` handoff to `http://<gateway>/<authdir>/`. The PIN is not placed in the
handoff or in a process argument. The host contract test passes, and the target
has the required PHP CGI, PDO SQLite, and `hash_pbkdf2` facilities; the live
uhttpd/openNDS authorization callback remains T003/T012 because a disposable
captive client has not yet completed the portal handoff.

The non-BinAuth adapter now encodes only the verified target `ndsctl auth` and
`ndsctl deauth` syntax. It converts internal seconds/bytes to the documented
minutes/kBytes units and is covered by a mock contract test. No permanent
router configuration was changed.

Evidence: official [FAS documentation](https://opennds.readthedocs.io/en/latest/fas.html),
target package/runtime inspection, the 2026-09-17 router POST test,
`tests/test_fas_contract.sh`, and `tests/test_opennds_adapter.sh`.

The BinAuth adapter now consumes the opaque FAS transaction atomically with
device admission and `active_sessions` creation. A target temporary-database
test accepted one v10.3.1-style callback, returned
`2/128/1024/2/4` in native minutes/kbit/s/kBytes, marked the transaction
`consumed`, created one active session, and rejected the duplicate callback.

The accounting branch is now implemented. A target temporary-database test
covered a 90,000-second daily session crossing midnight: it produced two
`usage_periods`, one `usage_events` row, one closed `active_sessions` row, and
aggregate totals of `90000` seconds, `2000` upload bytes, and `3000` download
bytes. Replaying the same callback left the event count at one.

The split allocation uses the official counter direction: incoming bytes are
download traffic and outgoing bytes are upload traffic. Non-final segments use
integer proportional allocation and the final segment receives the remainder,
so the aggregate never loses bytes due to rounding.

## 16. Phase 1 Foundation Evidence — 2026-09-16

The database initialization boundary now has an explicit schema version and a
numbered migration hook. A new or empty database is initialized from the
versioned schema; an existing database without `schema_meta`, or one newer
than the supported version, is rejected rather than overwritten. Future
migrations must be supplied as numbered SQL files and must advance
`schema_meta` one version at a time.

The period helper now emits UTC ISO-8601 boundaries in the format
`YYYY-MM-DDTHH:MM:SSZ` for hourly, daily, monthly, yearly, and unlimited
periods. Monthly and yearly rollover is calculated without relative-date
syntax because the target BusyBox `date` supports epoch conversion but rejects
inputs such as `+1 month`.

Evidence:

- Host shell syntax, quota, period, and domain tests pass.
- Target `sqlite3` 3.53.1 initialized a temporary v1 database idempotently and
  rejected an unversioned legacy database.
- Target ash/BusyBox produced valid hourly, daily, monthly, yearly, and `none`
  boundaries using the new helper.
- Target PBKDF2 benchmark and hash/verify smoke test passed with the selected
  100,000-iteration default.

## 17. Clean-router installation boundary — 2026-09-17

The package skeleton now has an explicit clean-router package plan and a
read-only preflight. The verified core plan is `opennds`, `sqlite3-cli`,
`php8-cgi`, `php8-mod-pdo-sqlite`, and `luci-base`; `dnsmasq-full` is not
installed or swapped in by the package. The preflight checks the required
commands and PHP modules, reports the openNDS version, and records failure
instead of guessing or changing network services.

The setup state machine currently implements the restartable base boundary:
`PREFLIGHT_OK` → `BASE_READY`, with `PREFLIGHT_FAILED` and
`DATABASE_FAILED` blockers. The package uci-defaults hook runs that base step
idempotently when the helper is present, while keeping `local_fas_enabled=0`.
This is intentional: a factory-reset router must first reach a verified base
state before the administrator explicitly activates the documented local FAS
path on port 2080. On the test router, that explicit activation was completed
after the base checks and was recorded with a reversible checkpoint.

Evidence: `tests/test_setup_plan.sh`, the shell syntax suite, the package
Makefile, and the official [FAS documentation](https://opennds.readthedocs.io/en/latest/fas.html).

The first LuCI boundary is now present at `Services → Open-HotSpot → Setup`.
It is intentionally read-only in this increment: it exposes the recorded setup
state, the verified package plan, the local-FAS plan, and the last blocker
without running package installation or shell commands during page rendering.
The device, voucher, dashboard, and history pages remain pending until their
management methods and the remaining live openNDS gates are closed.

The management boundary now includes `usr/libexec/rpcd/open_hotspot`. It uses
OpenWrt's documented executable rpcd plugin protocol: method arguments arrive
as JSON on stdin, and the plugin returns JSON on stdout. This keeps PIN input
out of command-line arguments while allowing LuCI to call bounded local
operations through ubus. The plugin currently covers profile and account
operations; device, voucher, dashboard, and history methods remain pending.

Evidence: `tests/test_admin_contract.sh`, `tests/test_rpc_contract.sh`, and
the official [OpenWrt rpcd plugin documentation](https://openwrt.org/docs/techref/rpcd).

## 18. Physical-router installation and local-FAS verification — 2026-09-17

The target is a Linksys EA8300 running OpenWrt 25.12.5 on
`ipq40xx/generic`, with openNDS 10.3.1. A verified backup was taken before the
state transition. The old unversioned database and legacy helper files were
archived, then the package initialized a clean v1 database and reached
`BASE_READY`.

Package `luci-app-open-hotspot 1.2.0-r15` was installed successfully. The
package's runtime plan is `opennds`, `sqlite3-cli`, `php8-cgi`,
`php8-mod-pdo-sqlite`, `luci-base`, and `luci-compat`; it does not depend on
`dnsmasq-full`. The local FAS activation created a separate uhttpd listener on
`0.0.0.0:2080`, selected secure level 1, removed the old remote-FAS fields,
and allowed only TCP/2080 to the router in `users_to_router` in addition to the
existing 2050/443 allowances. `ndsctl status` reports the local FAS URL and a
live openNDS daemon.

A proper HTTP client request (rather than the router's BusyBox `wget`, which
did not send a POST body in this environment) authenticated a temporary
account and produced the expected `tok`, `custom`, and `redir` handoff. The
temporary account was suspended, its pending transaction expired, and
`PRAGMA integrity_check` returned `ok`. This closes the runtime dependency and
local HTTP portions of T007, but not the full disposable-client T012 gate.

Submitting the same handoff from the management host to the openNDS `/nds/`
endpoint returned HTTP 511 and left `Current clients: 0`; this was not treated
as an authorization success because the host was not a separate captive client
on `br-lan`. A real Wi-Fi/LAN client must complete this final step.

Release r15 additionally normalizes the LuCI form layout across the custom
tabs and accepts `client_hid` as a compatibility alias for the documented
`hid` field. A FAS request without a verified payload is still rejected.
