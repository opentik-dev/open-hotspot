# Backup and restore contract

Open-HotSpot backup is deliberately a **manager-state** backup. It is not a
firmware image and must not be treated as a complete router migration.

## Contents

The archive contains exactly two members:

- `hotspot.db`: the SQLite database, copied with SQLite's online `.backup`
  operation;
- `open-hotspot`: the manager UCI policy.

The validator rejects path traversal, unexpected members, duplicate members,
missing members, an invalid SQLite integrity check, an unsupported schema
version, or a missing manager UCI section.

## Explicitly excluded

The archive does not include OpenWrt network/firewall/Wi-Fi settings,
openNDS/uhttpd configuration, FAS keys, SSH keys, LuCI/root credentials,
package versions, firmware slot state, or service state. This exclusion is
intentional: importing a manager database must not silently overwrite the
router's management plane or captive-portal identity.

## Security and portability

The archive is sensitive and unencrypted. It contains account credential
hashes, usage history, and device metadata. The export sets restrictive file
permissions (`0600`) on newly-created archives, but the operator must still
protect the downloaded file and remove copies after transfer.

The installed manager database and UCI policy are also forced to `0600` by
the package setup and service paths. This protects the live state on routers
whose default process umask is permissive.

An archive is portable only between installations that support the same
database schema and manager contract. On a new router, install and pass the
package preflight first, then validate/import the manager archive, run base
setup if required, and explicitly configure/activate local FAS. Never copy a
FAS key or network configuration from one router into another as an implicit
side effect of manager restore.

## Safe workflow

1. Export from the authenticated LuCI Backup page.
2. Keep the archive outside Git and verify its SHA-256 through a trusted local
   channel if it is transferred.
3. Use **Validate archive** before import.
4. Import only into the intended manager installation. The helper creates a
   pre-import rollback archive before replacing state.
5. Reload LuCI, run the read-only diagnostic, and verify the account/profile
   and history counts without exposing PINs, keys, or raw device identifiers.
6. Re-run the target-specific setup/FAS and captive-portal acceptance gates.

Import validation is not an acceptance result by itself. A production restore
also needs target evidence for rollback, service readiness, FAS, BinAuth,
accounting, and network-isolation behavior.
