# Unified-LAN authenticated-service pilot runbook

This runbook prepares the controlled `authenticated_users` experiment described
by [ADR-008](decisions/ADR-008-unified-lan-authenticated-service-pilot.md).
It does not make the shared-LAN profile a package default and does not replace
the production `br-hotspot` design.

## Preconditions

- Keep a second management path alive through `br-lan` or Tailscale.
- Use one disposable client; do not use a family device or the only admin
  session.
- Keep `br-hotspot` as the rollback path until U0–U5 pass.
- Disable VPN/WARP/private DNS on the disposable client for the baseline.
- Record the current UCI state and create the router backup through the existing
  guarded deployment/backup path. Never copy the archive or credentials into
  Git.

## U0 — read-only baseline

From the management path, capture sanitized output for:

```sh
uci -q get opennds.@opennds[0].gatewayinterface
uci -q show opennds.@opennds[0].authenticated_users
uci -q show opennds.@opennds[0].users_to_router
uci -q show firewall
ubus call network.interface dump
ubus call luci-rpc getDHCPLeases
ss -lntup
ss -lnup
ndsctl status
/usr/lib/open-hotspot/diagnose.sh
```

Derive the candidate service list from the listeners and application
configuration on the test day. Do not assume SMB/SIP/RTP ports, and do not add
any rule to `users_to_router` for NAS, PBX, camera, Tailscale, LuCI, or SSH.

## U1 — bridge and pre-auth gate

Change only the candidate gateway interface to the management bridge during a
short maintenance window. Keep the router-admin deny policy and the existing
FAS allowance unchanged. Confirm, before login, that the disposable client is
`Preauthenticated`, reaches `status.client`, and cannot reach the selected
service, LuCI, SSH, or the Internet. Roll back immediately if management is
lost or any service is reachable before authentication.

## U2–U4 — one authenticated rule at a time

Add exactly one narrow `authenticated_users` rule for one verified listener.
Test denial before login and access after login, then remove or retain the rule
only after recording the result. Repeat independently for SMB, SIP signalling,
RTP, and camera service paths. Test a Tailscale-originated service flow
separately; captive and IoT paths must remain denied.

## U5 — guest limitation

Test a guest account separately. If it receives the same authenticated service
access, record the native global-rule limitation and do not claim per-account
service isolation. Keep family/guest separation on distinct planes when that
distinction is required.

## Rollback and acceptance

On any unexpected reachability, service failure, or loss of management, stop
openNDS, restore the saved UCI/configuration archive, reload network/firewall,
restore the dedicated `br-hotspot` gateway, and verify portal and management
paths independently. The pilot is accepted only when U0–U5 evidence is
recorded; quota, reboot, and accounting gates remain separate.
