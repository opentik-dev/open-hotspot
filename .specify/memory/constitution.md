# Open-HotSpot Constitution

## Core Principles

### I. openNDS remains the enforcement engine

Open-HotSpot owns local identity, policy, accounting, and administration. It
must use openNDS native session, rate, and volume enforcement and must not
implement a custom packet counter or direct nftables quota enforcement.

### II. Target behavior must be evidenced

Any openNDS behavior not verified against the exact target OpenWrt package is a
Phase 0 gate. Production code must not guess BinAuth arguments, FAS custom
variables, quota units, or `ndsctl` syntax.

### III. Fail closed for new identity decisions

New authentication fails when identity, policy, or credential state cannot be
verified. Existing openNDS sessions retain their last applied state when the
manager, BinAuth, or maintenance job fails.

### IV. SQLite state is transactional and idempotent

All persistent state lives in SQLite. Accounting, voucher redemption, and
simultaneous-device admission use explicit transactions and unique constraints.
Repeated callbacks or interrupted jobs must not double-count or consume a
voucher twice.

### V. Security and privacy are defaults

PINs use the verified PBKDF2-HMAC-SHA256 implementation and are never logged,
stored in plaintext, passed to openNDS, or included in diagnostics. External
input is allow-list validated; shell SQL uses honest validation plus escaping,
not a claim of prepared-statement binding.

### VI. Small, auditable OpenWrt integration

Prefer POSIX shell, LuCI CBI, SQLite, and existing OpenWrt services. Scheduled
jobs are bounded, locked, idempotent, and run no more often than the configured
minimum interval of 60 seconds. `dnsmasq-full` is optional and feature-driven.

## Delivery Gates

Phase 0 target-build gates block openNDS integration work. Phase 1 database and
domain work may proceed independently, but no task may encode an unverified
openNDS contract. A release requires the Phase 0 evidence, automated domain
checks, and the real-router acceptance walkthrough in `quickstart.md`.

## Governance

This constitution governs implementation decisions and supersedes convenience
or assumptions from starter code. Changes to these principles require an
explicit update here and a corresponding update to the specification, plan,
or tasks when behavior is affected.

**Version**: 1.0.0 | **Ratified**: 2026-09-16 | **Last Amended**: 2026-09-16
