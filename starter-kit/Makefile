include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-open-hotspot
PKG_VERSION:=1.2.0
PKG_RELEASE:=112
PKG_SOURCE_DATE_EPOCH:=1790968682
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=Mohammed Al-Haddad <mohammed@example.com>

LUCI_TITLE:=LuCI support for Open-HotSpot (openNDS account/quota manager)
LUCI_DEPENDS:=+opennds +sqlite3-cli +php8-cgi +php8-mod-pdo-sqlite +luci-base +luci-compat
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk
# dnsmasq-full is a feature dependency, not a core dependency. The packaged
# dnsmasq-capability.sh check/install path is used only for autonomous
# walled-garden/blocklist features; base FAS/BinAuth/SQLite does not replace a
# working dnsmasq during installation.

# call BuildPackage - OpenWrt buildroot signature
