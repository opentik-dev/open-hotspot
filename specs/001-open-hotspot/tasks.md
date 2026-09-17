# Tasks — Open-HotSpot v1.2 Architecture-Corrected

**Legend**: `[P]` = parallelizable. **GATE** = blocking.  
**Rule**: no implementation task may encode an unverified openNDS behavior.

## Phase 0 — Target-Build Research and PoC

- [x] **T001 [GATE]** Identify the exact OpenWrt target architecture and exact
  `opennds` package/version/revision selected for testing. Record it in
  `research.md` and `quickstart.md`.
- [x] **T002 [GATE]** Capture the exact BinAuth method list, `auth_client`
  arguments/return semantics, and deauth/session-close argument contracts.
- [ ] **T003 [GATE]** Verify the local FAS authentication flow and exact redirect/
  custom-variable contract, including secure FAS options available on target.
- [x] **T004 [GATE]** Verify the supported native path for returning session length,
  upload/download rates, and upload/download volume quotas.
- [x] **T005 [GATE]** Verify `ndsctl auth` and `ndsctl deauth` syntax/units if these
  operations are needed outside BinAuth. Record exact commands; do not guess.
- [ ] **T006 [GATE]** Experimentally map openNDS incoming/outgoing counters to the
  project's upload/download fields.
- [x] **T007 [GATE]** Verify the local FAS runtime and all required CGI/runtime
  dependencies on the target router.
- [x] **T008 [GATE]** Verify a real PBKDF2-HMAC-SHA256 implementation exists in the
  target crypto package. If unavailable, stop rather than silently downgrade.
- [x] **T009 [GATE]** Benchmark the verified KDF on representative hardware and
  select/document the iteration count.
- [x] **T010 [GATE]** Determine whether the selected v1.2 feature set requires
  `dnsmasq-full`; do not install it by default.
- [ ] **T011 [GATE]** Test reboot and openNDS restart separately; record whether
  live sessions restore and distinguish that from SQLite usage persistence.
- [ ] **T012 [GATE]** Build a disposable end-to-end PoC proving portal → FAS →
  openNDS authorization → BinAuth → session close → SQLite accounting.
- [x] **T013 [GATE]** Prove that BinAuth contains no `ndsctl` call and that a
  BinAuth failure does not intentionally revoke an existing session.

**Phase 0 exit condition:** T001–T013 closed with evidence. If any gate fails,
update architecture/spec before Phase 1; do not code around the failure.

## Phase 1 — Database and Domain Layer

- [x] **T020** Implement `schema.sql`: profiles, accounts, devices,
  active_sessions, usage_periods, usage_events, auth_transactions, vouchers,
  admin_events, schema_meta.
- [x] **T021** Enable WAL, foreign keys, busy timeout, indexes, and required
  uniqueness constraints.
- [x] **T022** Implement migration/version handling and idempotent DB initialization.
- [x] **T023** Implement `db.sh` validation and SQL helpers using strict allow-lists
  and explicit escaping; document that this is not prepared-statement binding.
- [x] **T024** Implement voucher atomic redemption transaction.
- [x] **T025** Implement usage event insertion/dedup transaction.
- [x] **T026 [P]** Implement quota arithmetic in a testable helper.
- [x] **T027 [P]** Implement period boundary calculations in `period.sh`.

**Check:** schema contract tests pass locally. Real concurrent CLI tests remain
pending until the target `sqlite3-cli` environment is available.

## Phase 2 — Authentication and Native Enforcement Adapter

- [x] **T030** Implement `pbkdf2.sh` using the exact Phase 0 verified KDF.
- [ ] **T031** Implement `hotspot-login` POST parsing, validation, credential
  verification, expiry/status checks, and short-lived `auth_transactions`.
- [ ] **T032** Implement the verified openNDS FAS/authorization handoff from
  Gate B/C. Do not invent parameter names.
- [ ] **T033** Implement `opennds.sh` as the only non-BinAuth adapter for
  openNDS control operations.
- [ ] **T034** Implement authorization policy conversion from internal units to
  target openNDS units.
- [ ] **T035** Implement atomic simultaneous-device admission using
  `active_sessions` and the verified session identity model.
- [x] **T036** Implement `binauth.sh` method-specific parser for `auth_client`
  and all verified session-close methods.
- [x] **T037** Implement auth-context consumption in BinAuth without `ndsctl`.
- [x] **T038** Implement deauth accounting and `usage_events` deduplication.
- [x] **T039** Implement session close/update of `active_sessions` and `devices`.

**Check:** no `ndsctl` string/invocation in `binauth.sh`; end-to-end PoC passes.

## Phase 3 — Periods, Expiry, Recovery

- [ ] **T040** Implement period creation/rollover in `period.sh`.
- [x] **T041** Implement exact period-spanning accounting rules and tests.
- [ ] **T042** Implement `cycle.sh` with minimum 60 s interval and `flock -n`.
- [ ] **T043** Implement hard-expiry handling using `opennds.sh` outside BinAuth.
- [ ] **T044** Implement live policy refresh at period rollover only through the
  verified openNDS adapter.
- [ ] **T045** Implement `maintenance.sh` daily WAL checkpoint/retention/logging.
- [ ] **T046** Implement interrupted-job recovery and idempotent reruns.

**Check:** reboot, restart, rollover, expiry, and killed-job tests.

## Phase 4 — Setup and Packaging Skeleton

- [x] **T050** Implement setup preflight/state machine.
- [x] **T051** Implement explicit package planning based on Phase 0 requirements.
- [ ] **T052** Implement safe dependency installation and health checks; never
  remove base dnsmasq before a verified replacement is staged when replacement
  is actually required.
- [x] **T053** Implement idempotent `40-open-hotspot` initialization.
- [x] **T054** Implement init/service integration without a permanent polling loop.
- [x] **T055** Implement package metadata/Makefile with only verified dependencies.

## Phase 5 — LuCI Management UI

- [x] **T060** Implement LuCI controller/menu/ACL.
- [x] **T061 [P]** Implement `profiles.lua` CRUD and validation.
- [x] **T062 [P]** Implement `accounts.lua` CRUD, PIN update, profile/expiry/status.
- [x] **T063 [P]** Implement device list/block/remove/last-seen through the
  LuCI controller/RPC boundary. Removal is refused when session or usage
  history still references the device; blocking remains available instead.
- [x] **T064 [P]** Implement voucher batch generation/status/revoke through the
  LuCI controller/RPC boundary; redemption remains the existing atomic DB
  transition.
- [ ] **T065** Implement `status.lua` live dashboard merging openNDS live state
  with SQLite persistent state.
- [ ] **T066 [P]** Implement history view and backup/export/import validation.
- [ ] **T067** Implement setup UI with step state and safe action feedback.

## Phase 6 — Portal Templates

- [ ] **T070** Implement bundled English template.
- [ ] **T071** Implement bundled Arabic RTL template.
- [ ] **T072** Implement template validation and safe application through the
  openNDS-supported template mechanism.
- [ ] **T073** Test portal behavior with invalid credentials, expired account,
  exhausted quota, suspended account, and voucher redemption.

## Phase 7 — Security, Concurrency, and Release Validation

- [ ] **T080** Audit every portal-input field for validation and SQL safety.
- [ ] **T081** Verify PINs never appear in logs, process arguments, audit detail,
  or exported diagnostic files.
- [ ] **T082** Test simultaneous-device race with N+1 concurrent logins.
- [ ] **T083** Test voucher double-redemption race.
- [ ] **T084** Test duplicate BinAuth callbacks for one session.
- [ ] **T085** Test a session crossing a period boundary.
- [ ] **T086** Test manager/BinAuth/cycle failure while clients are connected.
- [ ] **T087** Test setup interruption/restart and package/service health.
- [ ] **T088** Run full `quickstart.md` acceptance procedure on real hardware.
- [ ] **T089** Perform Constitution traceability review.
- [ ] **T090** Freeze v1.2 implementation baseline only when every blocking
  acceptance criterion in `spec.md` is demonstrated.

## Definition of Done

The feature is not "done" because the package builds. It is done only when:

1. Phase 0 gates are evidenced on the actual target openNDS build.
2. BinAuth has zero `ndsctl` calls.
3. Native openNDS enforcement is demonstrated with measured limits.
4. Authentication identity is account-based, not MAC-based.
5. Simultaneous-device admission is race-safe.
6. Accounting is idempotent and period-aware.
7. SQLite persistence survives reboot without duplicate accounting.
8. Manager failure preserves existing openNDS authorization state.
9. Setup is restartable and does not unnecessarily replace dnsmasq.
10. LuCI and both portal templates work in the acceptance procedure.
