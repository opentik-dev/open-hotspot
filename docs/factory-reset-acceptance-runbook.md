# Runbook: Open-HotSpot factory-reset acceptance

**Owner:** Release engineer  | **Frequency:** Once per candidate router reset

**Last Updated:** 2026-10-09  | **Last Run:** Historical r88 run; physical acceptance remains pending

## Purpose

Install the exact field-candidate artifact recorded in
[`acceptance-state.json`](acceptance-state.json) on a disposable factory-reset OpenWrt router and
collect the evidence required to close the remaining spec-kit gates. This is a
pilot/acceptance procedure, not a production deployment procedure.

## Safety and prerequisites

- [ ] Confirm the exact router and serial/MAC with the operator; do not run the
      reset on a production or currently reachable router.
- [ ] Preserve any required configuration backup before pressing reset.
- [ ] Have an Ethernet admin laptop, a separate Wi-Fi/LAN client, and a WAN
      uplink available.
- [ ] Download the recorded field-candidate APK and `SHA256SUMS` from the matching GitHub Release.
- [ ] Have a traffic test endpoint available for both upload and download. If
      `iperf3` is used, place the server outside the router's management plane.
- [ ] Use a new root password before any client test.

## Dual-boot safety model

Use the two Linksys EA8300 slots as an A/B acceptance environment:

| Slot | Current role from the operator's inventory | Test role |
|---|---|---|
| 01 | Current rollback baseline | Protected r60/openNDS 10.3.1-r3 return path; do not overwrite. |
| 02 | Candidate | Factory-reset, install the recorded field candidate/openNDS 11.0.0, and run acceptance here. |

The table shows the same OpenWrt firmware in both slots, so slot 02 is not
automatically a clean factory image. Treat slot 01 as the protected rollback
baseline and record slot 02's state before resetting it. The two slots have
independent overlay filesystems:
SQLite data, UCI settings, portal activation, and Dropbear keys do not migrate
between them. Move application state with the project's backup/export flow,
not by assuming both slots see the same `/etc`.

Both slots may return the same factory-default management address after a
reset. The address is therefore not a slot identity. Discover it from the
current LAN or DHCP state and use a separate known-hosts file and a
separate administrator key for each slot:

```sh
SSH_STATE_DIR="${TMPDIR:-/tmp}/open-hotspot-ssh"
mkdir -p "$SSH_STATE_DIR"
chmod 700 "$SSH_STATE_DIR"
ssh-keygen -t ed25519 -f "$SSH_STATE_DIR/admin-slot-02" -N ''
ssh-keygen -t ed25519 -f "$SSH_STATE_DIR/admin-slot-01" -N ''
touch "$SSH_STATE_DIR/known_hosts.slot-02" "$SSH_STATE_DIR/known_hosts.slot-01"
chmod 600 "$SSH_STATE_DIR/known_hosts.slot-02" "$SSH_STATE_DIR/known_hosts.slot-01"
```

### Network address plan for the acceptance test

Do not connect a primary Wi-Fi router and the Open-HotSpot LAN with the same
address or subnet. Use this separation during the test:

| Function | Address/path |
|---|---|
| Primary Internet router | Its discovered upstream LAN/gateway |
| Open-HotSpot WAN/uplink | DHCP lease from the primary, or a Wi-Fi-STA/relay uplink |
| Open-HotSpot `br-lan` | A different non-overlapping LAN subnet |
| Admin laptop Ethernet | An address in the Open-HotSpot LAN, with no gateway/DNS on Ethernet |
| Admin laptop Wi-Fi default route | Primary router via its discovered gateway |

The Ethernet cable to the Open-HotSpot router is a management path only unless
it is connected to the router's WAN/uplink interface. A separate test client
must join the Open-HotSpot SSID or LAN to traverse openNDS; a client that stays
on the primary Wi-Fi will bypass the captive portal. The candidate preflight reports
and blocks duplicate local addresses, LAN equal to the default gateway, and
LAN/WAN subnet overlap; it does not rewrite network settings automatically.

Use these options for every connection; never reuse one `known_hosts` file or
one identity while changing slots:

```sh
TARGET_IP="${TARGET_IP:?Set TARGET_IP to the current slot management address}"

ssh -i "$SSH_STATE_DIR/admin-slot-02" \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile="$SSH_STATE_DIR/known_hosts.slot-02" \
  -o StrictHostKeyChecking=yes root@"$TARGET_IP" 'ubus call system board'

ssh -i "$SSH_STATE_DIR/admin-slot-01" \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile="$SSH_STATE_DIR/known_hosts.slot-01" \
  -o StrictHostKeyChecking=yes root@"$TARGET_IP" 'ubus call system board'
```

Before the first key-only connection to a slot, install that slot's public key
through the initial password-authenticated session and record the router host
key fingerprint. If SSH reports a host-key change at the discovered management
address, do not use
`ssh-keygen -R` against a shared file; select the other slot-specific file and
record the new fingerprint.

## Procedure

### 1. Freeze the delivered artifact

From the repository root, after downloading the APK and checksum file from the
matching GitHub Release:

```sh
RELEASE_DIR="${RELEASE_DIR:?Set RELEASE_DIR to the downloaded release directory}"
CANDIDATE_APK="${CANDIDATE_APK:?Set CANDIDATE_APK to the checksum-listed APK filename}"
test -f "$RELEASE_DIR/$CANDIDATE_APK"
sha256sum -c "$RELEASE_DIR/SHA256SUMS"
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
```

**Expected result:** the checksum is `OK` and all checks pass. Record the
terminal output with the test evidence.

**If it fails:** stop. Do not install a rebuilt, unverified, or differently
named APK.

### 2. Factory reset and establish admin access on candidate slot 02

While slot 01 is still current, record its identity and install/verify
`admin-slot-01.pub` through the existing administrator access. Then use
**System → Advanced Reboot** to boot alternative slot 02. Only after slot 02
is current may you physically reset the disposable candidate using its
vendor/OpenWrt procedure. Connect the admin laptop by Ethernet to the LAN
port, wait for the stock OpenWrt recovery window, and identify the LAN address
(normally supplied by the router's factory LAN configuration).

```sh
ssh root@"$TARGET_IP" 'ubus call system board'
ssh root@"$TARGET_IP" 'logread | tail -80'
```

**Expected result:** the board identity and OpenWrt version are captured. The
router is reachable by the admin plane only; no client is connected yet.

**If it fails:** stop and recover Ethernet/IP access before installing. Do not
change the package or reset again without recording the failure.

After the first login, verify the boot identity before installing the recorded
candidate. Capture
the Advanced Reboot page showing slot 02 as the current candidate and slot 01
as the protected rollback slot. Install `admin-slot-02.pub` and confirm that
key-only access works with the slot-02 known-hosts file.

For the remainder of the candidate test, define the slot-02 SSH command once
and use it for every router command:

```sh
SLOT02_SSH="ssh -i $SSH_STATE_DIR/admin-slot-02 -o IdentitiesOnly=yes -o UserKnownHostsFile=$SSH_STATE_DIR/known_hosts.slot-02 -o StrictHostKeyChecking=yes"
```

### 3. Prove the recovery slot and SSH separation

From the current slot's LuCI, open **System → Advanced Reboot**, select the
protected slot 01, confirm the reboot, and wait for the router to return.
Renew the admin laptop's DHCP lease if necessary; the expected management
address is again discovered from the current LAN/DHCP state.

```sh
ssh -i "$SSH_STATE_DIR/admin-slot-01" \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile="$SSH_STATE_DIR/known_hosts.slot-02" \
  -o StrictHostKeyChecking=yes root@"$TARGET_IP" 'ubus call system board'
```

**Expected result:** the router boots slot 01, the board identity and firmware
are recorded, and the slot-01 key works while the slot-02 key is not used. If
the two slots report the same firmware, record that fact; it does not prove the
filesystems or application state are shared.

Switch back to slot 02 through Advanced Reboot and verify the slot-02 key and
known-hosts file again. This is the candidate path; slot 01 is the rollback
path to use if slot 02 becomes unreachable after a reversible change.

**If it fails:** do not invent `fw_setenv` or partition commands. Use the
router's documented recovery/boot-selector procedure and keep the candidate
slot unchanged until access is restored.

### 4. Preflight the target and install the recorded candidate on slot 02

Copy and install the exact artifact:

```sh
tar -C "$RELEASE_DIR" -cf - "$CANDIDATE_APK" | \
$SLOT02_SSH root@"$TARGET_IP" 'tar -xf - -C /tmp'
$SLOT02_SSH root@"$TARGET_IP" "apk add --allow-untrusted /tmp/$CANDIDATE_APK"
$SLOT02_SSH root@"$TARGET_IP" 'uci set system.@system[0].hostname=open-hotspot-test; uci commit system'
$SLOT02_SSH -tt root@"$TARGET_IP" 'passwd'
```

**Expected result:** package installation completes without removing a base
`dnsmasq` package, and the operator sets a non-default root password.

**If it fails:** capture `apk`, `logread`, and `uci show open-hotspot`; do not
continue to client acceptance.

### 5. Run base setup and verify dependencies

```sh
$SLOT02_SSH root@"$TARGET_IP" '/usr/lib/open-hotspot/setup.sh base'
$SLOT02_SSH root@"$TARGET_IP" '/usr/lib/open-hotspot/setup.sh status'
$SLOT02_SSH root@"$TARGET_IP" '/usr/lib/open-hotspot/preflight.sh'
$SLOT02_SSH root@"$TARGET_IP" 'sh -c ". /usr/lib/open-hotspot/db.sh; db_init; db_schema_version"'
$SLOT02_SSH root@"$TARGET_IP" 'ubus -v list open_hotspot'
$SLOT02_SSH root@"$TARGET_IP" 'php-cgi -l /www/nds/fas.php'
```

**Expected result:** setup reaches `BASE_READY`, schema is `4`, the required
RPC methods are listed, PHP reports no syntax errors, and no silent partial
state is present. This supplies the static part of T052/T087.

**If it fails:** retain the output, run setup once more to test idempotence,
then use the rollback section. Do not mark T052/T087 closed.

### 6. Enable the local FAS deliberately

Use LuCI **Services → Open-HotSpot → Setup** to confirm the planned FAS
settings, then activate the local FAS only after the base checks pass:

```sh
$SLOT02_SSH root@"$TARGET_IP" '/usr/lib/open-hotspot/activate-local-fas.sh enable'
$SLOT02_SSH root@"$TARGET_IP" '/usr/lib/open-hotspot/activate-local-fas.sh status'
$SLOT02_SSH root@"$TARGET_IP" 'uci show opennds; netstat -lnt 2>/dev/null | grep 2080 || true'
```

**Expected result:** local FAS is enabled on the documented port and the
openNDS configuration remains target-compatible.

### 7. Prove the disposable client flow (T003/T012/T088)

From LuCI, create a short-lived profile and disposable account. Connect only
the separate Wi-Fi client to the hotspot SSID and browse to
`http://status.client`.

Record, in order:

1. The client is redirected to the portal with a valid FAS context.
2. A valid account login returns through the openNDS handoff.
3. `ndsctl status` shows the client as authenticated.
4. The router database shows one account-linked device and one active session.
5. Disconnect the client and confirm one close callback creates one usage event.
6. Repeat the close/retry trigger and confirm no duplicate usage event appears.

Router evidence commands:

```sh
$SLOT02_SSH root@"$TARGET_IP" 'ndsctl status'
$SLOT02_SSH root@"$TARGET_IP" 'logread | tail -120'
$SLOT02_SSH root@"$TARGET_IP" 'sqlite3 /etc/open-hotspot/hotspot.db ".headers on" ".mode column" "select username,status from accounts; select mac,account_id from devices; select account_id,device_id,started_at,closed_at,state from active_sessions; select event_key,bytes_incoming,bytes_outgoing from usage_events order by id desc limit 10;"'
```

**Expected result:** the complete portal → FAS → openNDS → BinAuth → close
path is demonstrated on a real client. Attach screenshots and command output
to the gate record.

**If it fails:** preserve the FAS POST/redirect status, `ndsctl status`,
`logread`, and the relevant database rows. Do not infer success from the FAS
page alone.

### 8. Map counters and native cutoff (T006)

Use a profile with a deliberately small, known limit. Generate a known
download and a known upload through the separate client and record the byte
counts from both the traffic endpoint and `ndsctl status`/usage rows.

**Expected result:** incoming/outgoing openNDS counters are mapped explicitly
to the project's upload/download fields, and the measured native cutoff is
within the acceptance tolerance defined in `spec.md`.

**If it fails:** leave T006 open and update the adapter/spec before shipping;
do not swap counter meanings in the UI by assumption.

### 9. Test restart and reboot separately (T011)

With a disposable client authenticated, collect the database and live state,
then run:

```sh
$SLOT02_SSH root@"$TARGET_IP" 'ndsctl status'
$SLOT02_SSH root@"$TARGET_IP" '/etc/init.d/opennds restart'
$SLOT02_SSH root@"$TARGET_IP" 'sleep 30; ndsctl status'
$SLOT02_SSH root@"$TARGET_IP" 'sh -c ". /usr/lib/open-hotspot/db.sh; db_init; sqlite3 \"$DB_PATH\" \"select count(*) from usage_events;\""'
$SLOT02_SSH root@"$TARGET_IP" 'reboot'
```

After the router returns, repeat the state queries and client check. Record
whether the live session survives each event and whether usage remains
persistent and non-duplicated. If the session is intentionally lost, record
that behavior and verify a fresh login is safe; the spec/release decision must
match the observed behavior.

### 10. Test A/B rollback after candidate acceptance

After collecting the candidate evidence, use Advanced Reboot to switch from
slot 02 to the protected rollback slot 01. Discover the new management address
and verify all of the following there:

1. The slot-01 host fingerprint is accepted only by `known_hosts.slot-01`.
2. The slot-01 administrator key works; the slot-02 identity is not silently
   substituted.
3. The expected recovery firmware and management plane are available.
4. Slot 01 does not show slot-02's SQLite accounts unless an explicit backup
   import was performed.

Switch back to slot 02 and verify the recorded candidate package, schema, and evidence are
still present. This demonstrates rollback availability without claiming that
an active client session survives a partition switch. A partition switch is a
router reboot and must be accounted for separately in T011.

If slot 02 is unhealthy but LuCI is still reachable, use Advanced Reboot to
select slot 01. If slot 02 is not reachable, use the vendor/OpenWrt recovery
procedure; do not send unverified bootloader commands.

### 11. Test failure containment (T086)

On this disposable target only, inject one failure at a time while a client is
already authenticated: manager/cycle availability, a BinAuth error path, and
an interrupted maintenance run. Restore the component after each injection.

**Expected result:** existing openNDS authorization is not revoked by manager
failure; new identity decisions fail closed; no duplicate usage is recorded;
the failure is visible in logs. Capture the exact injection and restoration
commands in the evidence record.

### 12. Complete Renew, MAC Reassign, backup, and release checks

Run the remaining quickstart steps for quota exhaustion, multi-device admission,
Renew, explicit MAC Reassign, voucher double redemption, backup export/import,
and the LuCI management-plane isolation check. Confirm LuCI works from the
admin plane and is unreachable from the client plane.

**Expected result:** every row in `docs/release-gates.md` has evidence, and the
operator records the final decision as either `GO` or `NO-GO`.

## Verification and handoff

- [ ] `docs/release-gates.md` contains evidence links/paths for every blocker.
- [ ] `specs/001-open-hotspot/tasks.md` changes to `[x]` only for demonstrated
      gates.
- [ ] `T090` is closed only after the complete physical-router acceptance.
- [ ] The router has a non-default root password and a recorded management IP.
- [ ] The installed APK checksum matches the `SHA256SUMS` file downloaded from
      the matching GitHub Release.
- [ ] Temporary test accounts, vouchers, and client data are removed or marked
      as intentionally retained test fixtures.

## Rollback

On a disposable target, first disable the deliberate local FAS activation:

```sh
$SLOT02_SSH root@"$TARGET_IP" '/usr/lib/open-hotspot/activate-local-fas.sh rollback'
$SLOT02_SSH root@"$TARGET_IP" 'apk del luci-app-open-hotspot'
```

If the target is being returned to a known factory state, use the vendor/OpenWrt
reset procedure again. Never delete `/etc/open-hotspot` or broad filesystem
paths as a substitute for the documented backup/restore process.

## Escalation

| Situation | Action |
|---|---|
| FAS page loads but no authenticated client appears | Keep T003/T012 open; attach redirect, `ndsctl status`, and logs. |
| Counters disagree with controlled traffic | Keep T006 open; do not reinterpret counters in code without target evidence. |
| Reboot loses sessions or duplicates usage | Keep T011 open; update the release decision and recovery behavior. |
| Setup/package interruption leaves partial state | Keep T052/T087 open; restore backup and record the exact failed state. |
| Any management surface is reachable from client plane | No-go; isolate management networking before further acceptance. |
| SSH rejects the host after switching slots | Use the slot-specific known-hosts/key pair; do not delete entries from a shared file. |
| Slot 02 lacks candidate accounts/configuration | Expected for independent overlays; use explicit backup/import if state migration is required. |

## History

| Date | Run By | Notes |
|---|---|---|
| 2026-09-23 | Open-HotSpot release process | Runbook aligned with the current A/B assignment: slot 02 is r88 candidate, slot 01 is r60 rollback; physical acceptance remains pending. |
