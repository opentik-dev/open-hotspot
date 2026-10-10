# External portal E2E smoke test

This is a deliberately small, deterministic browser check for the captive
portal page.  It complements, but does not replace, the repository contracts,
the router diagnostic, or physical-router acceptance evidence.

## Safety boundary

- It is never run by the package build or the existing shell/Python test suite.
- The runner has no router default: without `OPEN_HOTSPOT_E2E_URL`, it targets
  the closed local endpoint `127.0.0.1:9` and fails without touching a router.
- It has no AI agent, no API key, no stored credentials, and no admin action.
- The project command disables the framework's optional anonymous telemetry.
- Use a disposable client and test account. Do not save router, SIP, NAS,
  voucher, or Wi-Fi secrets in this directory.

## First use

Requires Node.js 22.22.3+ and pnpm. From the repository root:

```sh
pnpm install
cp tests/e2e/.env.example tests/e2e/.env
# Edit only the disposable portal endpoint, then export the variables.
set -a && . tests/e2e/.env && set +a
pnpm test:e2e:portal
```

The initial run may ask Playwright to obtain its browser runtime. This does not
change the router.

## What it proves

`portal-smoke.e2e.ts` proves that a browser can render the explicitly selected
portal endpoint. It does **not** prove authentication, quota enforcement,
openNDS firewall policy, NAS/SMB, Asterisk/SIP, camera reachability, Tailscale,
or WAN routing. Those remain separate router and field-acceptance gates.

## Planned staged expansion

Add each case only after recording the exact selector/contract and using a
disposable account:

1. Pre-auth captive redirect and portal identity.
2. Successful portal login and the expected session state.
3. Logout/expiry and accounting closure.

Keep selectors and assertions deterministic. Agent-driven E2E is optional and
must remain outside the default command because it needs a separately managed
model credential.
