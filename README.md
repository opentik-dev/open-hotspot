# Open-HotSpot — Spec-Kit Project (v1.2)

A LuCI management layer over **openNDS** for a single OpenWrt router:
accounts (with multiple devices each), quota/speed profiles, vouchers,
automatic cutoff, and a live dashboard — all local, SQLite-backed, no
RADIUS/external server. See `specs/001-open-hotspot/spec.md` for the full
specification.

## What changed from v1.0 (post architecture-review)
1. **Identity model fixed**: an Account is no longer a MAC address. It owns
   0..N `devices`, each with its own MAC, capped by `profiles.max_devices`.
2. **Local FAS flow closed the gap**: `www/nds/fas.php` verifies username+PIN
   locally (PIN never reaches openNDS or a log), creates an opaque one-time
   transaction, and hands BinAuth a verified identity via the custom variable
   — `binauth.sh` no longer trusts a bare MAC to mean a specific account.
3. **Password hashing corrected**: PBKDF2-HMAC-SHA256 (`pbkdf2.sh`, via the
   verified PHP `hash_pbkdf2` API) is the only accepted credential scheme. If
   the target's `php8-cgi` KDF path is unavailable, setup fails closed.
4. **`db.sh`'s security claim corrected**: it does allow-list validation
   (`_valid_ident`/`_valid_mac`/`_valid_int`) + SQL-string escaping, not
   SQLite parameter binding — v1.0's comment overclaimed this.
5. **SC-006 (no double-counting) now has a mechanism, not just a test**: the
   `usage_events.event_key` unique constraint with `INSERT OR IGNORE` gates
   every usage accrual — covered by the domain contract tests (two identical
   callbacks accrue once).
6. **Vouchers added to v1** (batch-generate, self-service redemption),
   using the same DB-native concurrency pattern (`UPDATE ... WHERE
   status='unused'`) — also smoke-tested here.
7. **`cycle.sh` trimmed**; WAL checkpoint/log rotation/pruning moved to a
   separate once-daily `maintenance.sh` so the fast tick stays minimal.
8. **`init.d/open-hotspot` clarified**: it registers/deregisters cron
   entries and exits — it is not a persistent daemon.
9. **Period-boundary behavior made explicit** (FR-006): a live session is
   never force-disconnected purely for a calendar rollover; `cycle.sh`
   reissues an updated ceiling at the next tick instead.
10. Two research items are now explicit **GATE**s in `tasks.md` (T002:
    `ndsctl auth` argument contract; T003: FAS custom-variable contract) —
    Phase 2 implementation may not start until they're confirmed against
    the openNDS build actually resolved from the OpenWrt 25.12.5 feed.

## Layout
Same spec-kit shape as before: `.specify/memory/constitution.md`,
`specs/001-open-hotspot/{spec,research,data-model,plan,quickstart,tasks}.md`,
and `starter-kit/` with a working schema + shell implementation of the
riskiest pieces (already smoke-tested for SQL-injection rejection and the
two concurrency guarantees — see commit history / test output).

## Physical-router checkpoint

The OpenWrt 25.12.5 SDK package was built as
`luci-app-open-hotspot 1.2.0-r16` and installed/tested on the Linksys EA8300 at
`192.168.70.1`. The local FAS listener is active on port `2080`; the exact
installation record, backup locations, SHA-256, rollback command, SDK/feed
procedure, and remaining live-client gates are in
[`specs/001-open-hotspot/quickstart.md`](specs/001-open-hotspot/quickstart.md).

The router's WAN is online through `192.168.50.1`, and `dnsmasq-full` is
installed with nftset support. The package intentionally does not replace
`dnsmasq` or silently alter the existing FAS configuration.

The tested APK is available at
[`dist/luci-app-open-hotspot-1.2.0-r16.apk`](dist/luci-app-open-hotspot-1.2.0-r16.apk)
with SHA-256
`cfc03526e5e8c9cfe6dace0968b24ff4e63aabeab72144232196ed0ded7ad16a`.

Release r16 also accepts the documented openNDS `hid` field and the
`client_hid` compatibility spelling observed in some captive-client flows.
Requests without a verified FAS payload remain rejected.

### Captive-portal URL contract

The built-in openNDS client-status page is available at
`http://status.client`; the package configures this hostname to resolve to the
router LAN address (`192.168.70.1`). The custom Arabic/English login page is
served by the local FAS endpoint at `/nds/fas.php`, but it must be opened by
the openNDS captive-portal flow so that the documented FAS context is present.
Opening `/nds/fas.php` directly, or when a captive-client probe omits the FAS
payload, intentionally shows the styled “missing FAS data” page and does not
authenticate the client. Use the page's **Open portal** button or navigate to
`http://status.client` over plain HTTP, then submit the login form.

The screenshot showing the “missing FAS data” card is therefore a captured
fail-closed diagnostic page, not evidence that the FAS page is absent from the
APK. The remaining physical-router gate is a successful disposable-client
session: portal → FAS login → openNDS `Authenticated` state.

## Distribution

The OpenWrt APK is not a GitHub Packages format. GitHub Packages currently
supports npm, RubyGems, Maven/Gradle, NuGet, Docker, and OCI registries, so the
repository's Packages page correctly remains empty. The APK is distributed as
a repository artifact and, when a `v*` tag is pushed, the included workflow
publishes it as a GitHub Release asset. See [Releases](https://github.com/opentik-dev/open-hotspot/releases).

## LuCI screenshots

These screenshots were captured from the installed package on the test router.
The yellow banner is intentional: the router still needs a root password before
handoff.

![Open-HotSpot setup](docs/screenshots/setup.jpg)

![Open-HotSpot profiles](docs/screenshots/profiles.jpg)

![Open-HotSpot accounts](docs/screenshots/accounts.jpg)

![Open-HotSpot devices](docs/screenshots/devices.jpg)

![Open-HotSpot vouchers](docs/screenshots/vouchers.jpg)

## Continue with the real spec-kit CLI
```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
cd open-hotspot
specify init --here --integration claude
```
Then, in order: `/speckit.plan` → `/speckit.tasks` → `/speckit.analyze` →
`/speckit.implement`. Close GATE T002 and GATE T003 first (`research.md`)
— everything else in Phase 2 depends on their exact answers.
