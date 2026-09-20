# Open-HotSpot

Open-HotSpot is a local captive-portal and hotspot management system for
OpenWrt, built around [openNDS](https://opennds.readthedocs.io/) and managed
through LuCI.

It provides local accounts, multiple devices per account, vouchers, bandwidth
profiles, aggregate quotas, automatic access control, usage history, and a live
dashboard without RADIUS, cloud services, or an external database.

> **Status: pre-production acceptance candidate.**
>
> The project has a working implementation and a substantial automated test
> suite, but the physical-router gates listed in [`docs/project-status.md`](docs/project-status.md)
> are not all accepted yet. Do not treat the current candidate as a production
> baseline until the release gates are closed.

## Why Open-HotSpot?

Small hotspot networks should not need a cloud subscription or a separate
authentication server. Open-HotSpot keeps identity, policy, accounting, and
administration on the OpenWrt router while delegating captive-portal and
traffic enforcement to openNDS.

## What you get

| Capability | Description |
|---|---|
| Accounts | Local username and PIN accounts |
| Multiple devices | Several devices associated with one account |
| Vouchers | Atomic one-time voucher redemption |
| Profiles | Time, rate, quota, and device-limit policies |
| Quotas | Aggregate account usage by period |
| Automatic cutoff | New access is denied when a budget is exhausted |
| Dashboard | Live openNDS state combined with SQLite history |
| Local authentication | No RADIUS, cloud, or external auth service |
| LuCI | Native OpenWrt administration interface |
| Arabic portal | Bundled Arabic RTL and English templates |

## How it works

```text
Client
  │
  ▼
openNDS captive portal
  │
  ▼
Open-HotSpot local FAS ── verify account/PIN ── SQLite
  │
  ▼
verified openNDS authorization
  │
  ▼
openNDS enforcement ── BinAuth events ── usage/accounting in SQLite
  │
  ▼
LuCI / RPC administration
```

The architectural boundary is deliberate: openNDS remains the enforcement
engine, while Open-HotSpot owns local identity, policy, accounting, and
management. BinAuth is event-driven and must not call `ndsctl`.

## Current target candidate

The recorded acceptance baseline is:

```text
Router:       Linksys EA8300
OpenWrt:      25.12.5
Target:       ipq40xx/generic
openNDS:      10.3.1-r3
Open-HotSpot: 1.2.0-r60
```

The router address is discovered from the current LAN configuration; it is not
part of the FAS contract. The two-slot layout is used as an A/B rollback aid,
not as shared application storage.

## Installation and first use

Use the [factory-reset acceptance runbook](docs/factory-reset-acceptance-runbook.md)
for a disposable router. It covers the A/B slots, separate SSH identities,
dynamic management addresses, package verification, setup recovery, and field
evidence.

After installing the verified APK on the candidate router:

1. Open **Services → Open-HotSpot → Setup**.
2. Run the preflight and base setup checks.
3. Create a profile with a period, rate, quota, and device limit.
4. Create an account and register its client device.
5. Connect a test client to the Open-HotSpot LAN/SSID, not the upstream Wi-Fi.
6. Open the captive portal, authenticate, and inspect the session in LuCI.

Never use a fixed router address in scripts or documentation. Keep the admin
plane and client/IoT plane on non-overlapping networks.

## Screenshots

The repository includes LuCI screenshots for [accounts](docs/screenshots/accounts.jpg),
[devices](docs/screenshots/devices.jpg), [profiles](docs/screenshots/profiles.jpg),
[setup](docs/screenshots/setup.jpg), and [vouchers](docs/screenshots/vouchers.jpg).

## Development

The project uses specification-driven development. Spec-Kit documents
requirements and engineering decisions; it is not the product identity shown to
users.

- [Development guide](docs/development.md)
- [Project status and open gates](docs/project-status.md)
- [Acceptance runbook](docs/factory-reset-acceptance-runbook.md)
- [Release gate register](docs/release-gates.md)
- [Release history](docs/release-history.md)
- [OpenNDS 11 migration decision](docs/decisions/ADR-003-opennds-v11-migration.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

Before handoff, run:

```sh
python3 -m unittest discover -s tests -v
sh tests/test_shell_syntax.sh
sh tests/test_quota.sh
```

Run the complete `tests/test_*.sh` contract suite when changing adapters,
setup, packaging, security boundaries, or release documentation.

## Maintainer

Open-HotSpot is maintained and developed by **Mohammed Al-Haddad**, with
contributions from the open-source community.

## License

The package is distributed under the [GPL-2.0-or-later](LICENSE) license.
