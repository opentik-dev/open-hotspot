# Field evidence — 2026-09-22

Target: Linksys EA8300, OpenWrt 25.12.5, openNDS 11.0.0, current slot
`boot_part=2`, management address discovered for this run as `192.168.2.1`.
The package does not store or require that address.

## r78 acceptance slice

- Transfer used SSH plus `tar`; `scp` was not retried because the target has no
  `sftp-server`.
- r78 installed successfully and the read-only diagnostic reported healthy
  openNDS, uhttpd, local FAS, and the versioned adapter.
- Direct Ethernet HTTP interception reached the local FAS: GET `200`, login
  POST `200`, openNDS handoff `307`.
- The target reported one Authenticated client and one active manager session;
  the dashboard/device boundary was therefore physically observed.
- The package deauth control returned success. After the target callback,
  openNDS clients changed from one to zero, active SQLite sessions from one to
  zero, and usage events increased from one to two.
- The latest usage event had method `ndsctl_deauth`; its byte counters were
  persisted. No PIN, FAS key, raw MAC, raw token, or backup is recorded here.
- Final diagnostic: `failures=0 warnings=0`, `fasremoteip=unset`,
  `fasremotefqdn=status.client`, openNDS `11.0.0`, and zero current clients.

## Root cause closed

The r77 run exposed that the target's deauth callback carries the base64
marker for an empty custom field. r78 accepts only that explicit marker and
resolves the sole active session for the callback MAC in SQLite. Arbitrary or
unknown custom data still fails closed. The IP lookup in r77 remains required
for the target's `ndsctl deauth` control path.

## Gates still open

T006 still needs controlled upload/download quota cutoff evidence. T011 still
needs the separate restart/reboot matrix and duplicate-callback evidence.
T052/T087, T086, T088, and T090 still require their physical acceptance
procedures. Internet reachability through the upstream WAN was not claimed in
this Ethernet-only probe because the host's default route is on another
interface; phone testing with VPN/mobile data disabled remains required.
