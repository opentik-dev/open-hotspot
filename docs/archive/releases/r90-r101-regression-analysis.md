# r90 to r101 regression analysis

**Date:** 2026-10-09
**Scope:** Determine whether a change after the historical r90 candidate can
explain loss of router-hosted NAS, PBX, camera, or modem access.

## Evidence boundary

The repository does not contain a Git source revision whose package metadata is
`1.2.0-r90`; the commit historically associated with the r90 field work still
declares package release r78. A local r90-labelled APK is available for
read-only inspection, but its SHA-256 does **not** match the r90 checksum
recorded in the operational ledger. It is therefore evidence of file contents,
not an approved rollback artifact and must not be installed.

| Artifact | SHA-256 | Status |
|---|---|---|
| Historical r90 checksum in ledger | `1fe185ee21849742eb526bdc73d4480146d57c7a39d4c9284eb3053453174ccc` | Authoritative historical record |
| Local r90-labelled APK | `ad6cc1d142891bd1092e6f6e468a7623e5233be903cf81543896c380fab9bfb6` | Mismatch; do not deploy |
| r101 installed candidate | `8b720d2c9ac54247c7a384e86903ca91b3b1b3b7085cd62dc4d426ca1c97de40` | Reproducible and field-installed |

## Package comparison

The two APKs were extracted locally for inspection only.

| Component | Result | Relevance to reported reachability |
|---|---|---|
| `/etc/config/open-hotspot` | Identical content hash | r101 did not change the package default manager configuration. |
| `/www/nds/fas.php` | Identical content hash | r101 did not change the FAS page or credential handoff endpoint. |
| `activate-local-fas.sh` | Only removes an old `chmod 600` call | No change to FAS hostname, port, redirect, or firewall allowance. |
| `opennds.sh` | Adds normalized live-MAC output and an `Authenticated`-only client parser | Prevents preauthenticated probes from being treated as active sessions; it does not add router-service blocking. |
| `router-access.sh` | Adds an optional dedicated-client/IoT → WAN forwarding rule | It is inactive unless an administrator applies it to a separate UCI network. Target evidence records no selected client network or forwarding section. |
| KSMBD/Asterisk/camera configuration | Not packaged or modified by Open-HotSpot | Their listener/process state is outside the package boundary. |

## Conclusion

The evidence does **not** support r101 as the cause of the router-hosted
service failures. The current findings remain independent:

- KSMBD has a mounted share but no listener on the router LAN address.
- Asterisk PJSIP reports UDP port 5060 while the supplied phone configuration
  uses UDP port 5062.
- The camera has a layer-2 neighbor entry but its configured TCP port does not
  accept a connection from the router.
- The router itself has a WAN route to the upstream modem; client-side access
  requires a separate client-path test.

Do not roll back to the local r90-labelled APK. It would replace an auditable,
reproducible r101 artifact with an unverified package and would not be a
justified repair for the identified service listener/configuration failures.

## Safe next action

Retain r101. Test the SIP phone on UDP 5060, repair KSMBD at its package/runtime
boundary, and check the camera service/power/port independently. If a future
comparison requires a historical rollback, first obtain an APK whose checksum
matches the recorded r90 artifact and run the guarded rollback procedure from
an alternate management path.

## Verified r50 historical comparison

The local `r50` APK has SHA-256
`fe8860b11e840b40fc1bdb6d21dcedc5a4b164b38133664b48394856ee951177`,
which matches the release ledger. It is therefore suitable for **read-only
comparison**, but it is not compatible for an in-place rollback over the
current target without also restoring the matching openNDS baseline.

| Area | r50 | r101 | Interpretation |
|---|---|---|---|
| openNDS contract | Explicitly targets openNDS 10.3.1-r3 | Versioned adapter supports the target's 11.0.0 contract | This is a daemon compatibility transition, not a cosmetic package revision. |
| Local FAS remote FQDN | Removes `fasremotefqdn` | Sets `fasremotefqdn=status.client` for openNDS 11 mode 0 | Installing r50 against the current openNDS 11 configuration can break the portal rather than restore services. |
| Router-access policy | Absent | Optional helper, inactive unless a dedicated UCI client network is selected | Target evidence shows no selected client network or generated forwarding, so this cannot explain the current reachability findings. |
| Manager boot/restore | No manager restore/reconcile invocation | Bounded restore/reconcile hooks outside BinAuth | This changes session lifecycle handling, not KSMBD, Asterisk, camera, or modem listeners/routes. |

The historical claim that services worked before remains plausible as a report
of an earlier **whole-router state**, especially before the openNDS 10.3 → 11
migration. The artifact comparison does not prove that r101 caused their
failure. It proves that r50 is a different openNDS integration baseline and
must not be used as a one-package rollback on the current router.
