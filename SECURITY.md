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

## Supported baseline

The documented acceptance baseline is Open-HotSpot 1.2.0-r60 on OpenWrt 25.12.5
and the recorded openNDS target package. openNDS 11 is a proposed, isolated
compatibility track; do not install an unverified architecture or package on
the acceptance router.
