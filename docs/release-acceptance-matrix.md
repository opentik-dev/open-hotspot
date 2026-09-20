# Release acceptance matrix

This is the single release view connecting the requirement to implementation,
test, field evidence, and the release decision. A row is not closed until all
five columns contain evidence. Source-only implementation is never sufficient
for a target/runtime gate.

| Requirement | Task / implementation | Automated test | Field evidence | Release gate / decision |
|---|---|---|---|---|
| FR-001–004: restartable setup and dependency checks | `setup.sh`, `preflight.sh`, `40-open-hotspot` | `test_setup_plan.sh`, `test_install_contract.sh`, `test_topology_contract.sh` | Factory-reset runbook setup transcript | T052/T087 in `docs/release-gates.md` |
| FR-010–017: accounts, devices, Renew, MAC Reassign | `admin.sh`, LuCI accounts/devices pages, RPC methods | `test_admin_contract.sh`, `test_rpc_contract.sh`, schema tests | Disposable account/device flow | T012/T088; MAC/Renew rows |
| FR-020–025: profiles and aggregate quotas | `quota.sh`, `opennds.sh`, `cycle.sh` | `test_quota.sh`, `test_opennds_adapter.sh` | Controlled upload/download and cutoff measurement | T006 |
| FR-030–035: FAS identity and fail-closed BinAuth | `fas.php`, `binauth.sh`, `custombinauth.sh` | `test_fas_contract.sh`, `test_binauth_contract.sh`, `test_security_contract.sh` | Portal → FAS → openNDS → BinAuth login | T003/T012 |
| FR-040–044: idempotent accounting and persistence | SQLite schema, migrations, BinAuth close path | `test_schema.py`, `test_db_init.sh`, `test_period.sh` | Session close, duplicate callback, reboot usage comparison | T006/T011/T012 |
| FR-045: configurable reboot session restore | `session-restore.sh`, LuCI Setup option | `test_session_restore_contract.sh` | E-013 enabled and disabled reboot tests | T011; partial until restart/accounting evidence |
| FR-050–053: maintenance and force-deauth | `opennds.sh`, `cycle.sh`, `maintenance.sh` | `test_opennds_adapter.sh`, shell syntax | Connected-client deauth and manager-failure test | T086/T088 |
| FR-070–073: LuCI and backup/import | LuCI controller/views, `backup.sh` | `test_luci_contract.sh`, `test_backup_contract.sh` | Authenticated LuCI backup/restore on target | T066/T088 |
| NFR-005: secrets and management isolation | FAS key handling, router-access policy | `test_security_contract.sh`, `test_router_access_contract.sh` | IoT/client network cannot reach admin ports; WARP retest | High router-access/WARP gates |
| NFR-006: recoverability | init scripts, APK post-install/upgrade | all shell/install contracts | Interrupted setup, upgrade, reboot, A/B rollback | T052/T087 and A/B gate |
| Release stop: no unsafe production claim | release gate register and delivery manifest | CI green plus artifact checksum | Physical factory-reset acceptance | T090; blocked while any critical gate is open |

## Status rule

The authoritative status is `docs/release-gates.md`. This matrix is updated in
the same change as a gate decision, and the delivery manifest must link the
matching evidence. A release tag does not override an open gate.
