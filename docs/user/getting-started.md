# Getting started

This guide explains the product flow. Use the
[factory-reset acceptance runbook](../factory-reset-acceptance-runbook.md) for
an actual disposable-router installation; it contains the safety checks,
rollback steps, and field-evidence requirements.

## Administrator flow

1. Open **Services → Open-HotSpot → Setup** in LuCI.
2. Run preflight and base setup checks and review every reported result.
3. Create a profile with its period, time/data budgets, rates, and device
   limit.
4. Create an account and assign the profile.
5. Register or review the client device under that account.
6. Connect a disposable client to the captive network and complete the local
   portal login.
7. Confirm the live session in Devices/Dashboard before testing traffic.
8. Review usage history after the session closes.

## What the administrator should expect

- A profile budget is aggregated at account/period level, not independently
  per device.
- openNDS applies native per-session limits after the verified authorization
  handoff.
- A duplicate callback must not create a second usage event.
- A failed manager decision must not intentionally destroy an already
  authorized session.
- A successful local test is not by itself physical acceptance; the matching
  release gate still needs its specified target evidence.

## Before a field test

- Use a disposable client and the documented management path.
- Do not use VPN/WARP or mobile data during portal verification.
- Preserve the documented rollback baseline.
- Do not enable experimental Family Captive or shared-LAN service paths unless
  their separate acceptance procedure explicitly authorizes the test.

For implementation details, see the
[architecture overview](../architecture/overview.md) and
[development guide](../development.md).
