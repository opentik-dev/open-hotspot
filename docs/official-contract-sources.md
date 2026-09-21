# Official contract sources

This file is the first stop before changing an integration boundary. A local
memory, a screenshot, or an old router transcript is not a substitute for the
upstream contract. When the target version differs from the page version, the
target's installed script/source must be captured in `specs/001-open-hotspot/research.md`
and the difference must be recorded in `docs/integration-gap-register.md`.

## openNDS

- [FAS — openNDS v11](https://opennds.readthedocs.io/en/latest/fas.html):
  `fasport`, `fasremoteip`, `fasremotefqdn`, `faspath`, `fas_secure_enabled`,
  and `faskey`; local FAS must not use port 80.
- [Configuration options — openNDS v11](https://opennds.readthedocs.io/en/latest/config.html):
  UCI option names, local FAS behavior, BinAuth output variables, and native
  quota units.
- [BinAuth — openNDS](https://opennds.readthedocs.io/en/stable/binauth.html):
  callback methods, argument layouts, `custombinauth.sh`, and the warning not
  to replace the stock `binauth_log.sh` when `auth_restore` is required.
- [Traffic and quota behavior — openNDS](https://opennds.readthedocs.io/en/stable/traffic.html):
  upload/download direction, rate units, quota units, and the fact that the
  FAS/BinAuth custom variable has no universal payload format.

## OpenWrt

- [uHTTPd](https://openwrt.org/docs/guide-user/services/webserver/http.uhttpd):
  service role, `/etc/config/uhttpd`, CGI/PHP serving, and UCI-based setup.
- [uHTTPd configuration](https://openwrt.org/docs/guide-user/services/webserver/uhttpd):
  multiple named instances and listener requirements.
- [UCI technical reference](https://openwrt.org/docs/techref/uci):
  configuration ownership and scriptable UCI changes.
- [LuCI essentials](https://openwrt.org/docs/guide-user/luci/luci.essentials):
  LuCI/uHTTPd package relationships and service reload expectations.

## Review rule

For every proposed fix, record: official page reviewed, target version, local
observation, chosen implementation, automated check, and field evidence. A
fix is `Implemented` only after code exists; it is `Accepted` only after the
physical-router evidence closes its release gate.
