# Reboot session restore

Open-HotSpot now exposes **Restore authenticated sessions after reboot** in
LuCI under **Services → Open-HotSpot → Setup**. The default is **Disabled**;
clients must log in again after a router or openNDS restart.

When enabled, the manager performs a one-per-openNDS-process restore from its
SQLite state:

1. It selects only active devices belonging to active, non-expired accounts.
2. It calculates the current period's remaining time, upload, and download
   budgets.
3. It refuses to restore an exhausted policy.
4. It applies the verified `ndsctl auth` policy through
   `/usr/lib/open-hotspot/opennds.sh`, outside BinAuth.
5. It keeps the existing SQLite session key so later deauthentication is
   accounted once against the original session.

The restore is keyed by the current openNDS process/boot state and never by a
router IP address. It is retried after startup ordering failures and after an
openNDS process replacement. Enabling or disabling the option does not
disconnect an already authenticated client; the setting controls future
restore attempts.

This implementation intentionally does not rely on openNDS's stock
`auth_restore` log database. The official documentation says the default local
log mountpoint is volatile tmpfs and warns against silently writing frequent
logs to built-in flash. It also documents that replacing the default BinAuth
script disables stock `auth_restore`; therefore the manager keeps identity,
policy, and accounting in SQLite and restores through its already verified
control adapter instead.

The security trade-off is explicit: enabling restore allows an active account's
device to regain its remaining policy without entering the portal after a
restart. Suspension, expiry, exhaustion, or a missing database policy prevents
restoration. A new device or unknown MAC still requires the normal FAS login.

References:

- [openNDS BinAuth and auth_restore](https://opennds.readthedocs.io/en/stable/binauth.html)
- [openNDS auth_restore library](https://opennds.readthedocs.io/en/stable/libraries.html)
- [openNDS local log mountpoint warning](https://opennds.readthedocs.io/en/stable/config.html)
- [openNDS ndsctl authentication](https://opennds.readthedocs.io/en/stable/ndsctl.html)
