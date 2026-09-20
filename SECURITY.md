# Security policy

Open-HotSpot handles hotspot credentials, captive-portal input, SQLite state,
OpenWrt package installation, and router-management boundaries.

## Reporting

Do not publish credentials, FAS keys, backups, client identifiers, or detailed
exploitation steps in a public issue. Report a suspected vulnerability to the
maintainer privately through the repository owner, including the affected
commit/package, target OpenWrt/openNDS versions, reproduction steps, impact,
and a safe mitigation if known.

## Security boundaries

- PINs are stored using the verified PBKDF2-HMAC-SHA256 path and must not be
  logged, passed to openNDS, or included in diagnostics.
- New authentication fails closed when identity or policy cannot be verified.
- BinAuth must not call `ndsctl` or manipulate firewall state.
- Router administration and client/IoT networks must be explicitly separated.
- Local FAS keys are generated/stored on the target and are never committed.
- Backup/import paths must validate archives before replacing state.
- A physical-router result is not accepted from source inspection alone.

## Supported tracks

The current acceptance candidate is Open-HotSpot 1.2.0-r74 on OpenWrt 25.12.5
with the verified openNDS 11.0.0 target contract. Open-HotSpot 1.2.0-r60 with
openNDS 10.3.1-r3 remains the rollback baseline. Keep the tracks isolated and
do not replace the rollback slot in place. See
[`docs/current-state.md`](docs/current-state.md) for the authoritative state.
