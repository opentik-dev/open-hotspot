# DNS Insights — implementation and decision record

**Status:** Design only — disabled

**Owner:** Open-HotSpot engineering and release owner

**Scope:** Local DNS requests observed on the Open-HotSpot client network,
correlated to an active Open-HotSpot session when that correlation is reliable.
This is observability, not filtering, quota enforcement, or a substitute for
openNDS accounting.

## Decision summary

openNDS v11 exposes captive-portal, FAS, BinAuth, session, and quota events; it
does not provide a supported per-account DNS-query stream through `ndsctl`.
The implementation must therefore treat the local DNS resolver as the source
of DNS observations. openNDS remains the enforcement engine and no DNS feature
may add packet counters, nftables quota rules, or a BinAuth poller.

The feature is disabled until the decision gates below are accepted. Adding a
visual control to DEV must never activate collection.

## Proposed bounded design

1. Capture only queries handled by the router's local resolver (initially
   dnsmasq), using a documented resolver logging interface or a dedicated
   bounded hook. Do not scrape raw `logread` as an application API.
2. Correlate a query to the source IP and then to the active session/device
   mapping at observation time. If the mapping is missing or ambiguous, label
   the row `unattributed`; never guess the account from a stale MAC.
3. Store a bounded ring buffer with configurable maximum rows and retention.
   Default state is disabled, and enabling requires an explicit administrator
   action with an audit event.
4. Redact or normalize sensitive material before persistence and display. Do
   not store query parameters, credentials, FAS tokens, or raw resolver logs.
5. Expose a read-only LuCI page with filters for time, account, and domain
   suffix, plus a clear collection-state indicator. The RPC must cap rows and
   output size and must not execute shell input from the browser.
6. Keep DoH/DoT and external DNS outside the guarantee. The page must state
   that encrypted or bypassed DNS is not visible to this collector.
7. Keep the feature independent from walled-garden/blocklist configuration;
   observing a domain must not allow or block it.

## Required decision gates

| Gate | Question | Evidence required | State |
|---|---|---|---|
| DNS-01 | Is the target resolver capable of bounded query logging without replacing core dnsmasq? | Target package/config probe and memory/flash estimate | Open |
| DNS-02 | Can source IP be correlated to the current device/session without stale attribution? | Controlled client test with login, DHCP renewal, and disconnect | Open |
| DNS-03 | Are retention, redaction, administrator access, and export rules acceptable? | Approved privacy/operations decision | Open |
| DNS-04 | Does the collector remain bounded under query load? | Synthetic load and row/output cap test | Open |
| DNS-05 | Does disable/rollback remove collection without disturbing openNDS sessions? | Disable and rollback transcript | Open |
| DNS-06 | Are DoH/DoT and bypass limitations visible in the UI and documentation? | UI contract and operator acceptance | Open |

## Failure handling and rollback

- If the resolver interface is unavailable, collection remains disabled and
  existing client sessions are untouched.
- If correlation fails, keep the event unattributed; do not deny service.
- If storage reaches its cap, evict oldest rows or stop collection safely;
  never grow without a bound and never block DNS resolution.
- If the collector crashes, openNDS, FAS, BinAuth, and quota behavior must
  continue unchanged.
- Rollback removes the collector, its UCI state, its database objects, and its
  LuCI/RPC surface while preserving account/session/usage data.

## Implementation stages

1. **Research:** run DNS-01 and document the exact target resolver contract.
2. **Contract:** add schema, redaction, retention, ACL, and bounded-RPC tests;
   no target activation.
3. **Isolated prototype:** implement behind an explicit disabled feature flag
   and test with synthetic resolver input only.
4. **Target pilot:** enable only on a disposable client network after DNS-01 to
   DNS-06 pass; record sanitized results in `docs/operational-ledger.md`.
5. **Release decision:** keep disabled unless all gates and privacy decisions
   are accepted; do not include it in the production acceptance baseline by
   implication.

## Current progress log

- 2026-10-03: Plan created. DEV registry entry added as design-only/disabled.
- 2026-10-03: No DNS collector, raw-log reader, resolver mutation, or router
  activation performed.
- 2026-10-03: Official openNDS documentation confirms FAS/BinAuth and native
  quota interfaces, plus FQDN walled-garden/blocklist features; none is a
  per-account DNS history API.
- 2026-10-03: r97 target deployment confirmed the feature remains design-only;
  no resolver logging was enabled and no DNS collector files were installed.

## References

- `docs/official-contract-sources.md`
- `docs/router-access-and-iot.md`
- `docs/operational-ledger.md`
- openNDS v11 FAS and configuration documentation
