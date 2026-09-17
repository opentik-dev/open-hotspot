include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-open-hotspot
PKG_VERSION:=1.2.0
PKG_RELEASE:=14
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=

LUCI_TITLE:=LuCI support for Open-HotSpot (openNDS account/quota manager)
LUCI_DEPENDS:=+opennds +sqlite3-cli +php8-cgi +php8-mod-pdo-sqlite +luci-base +luci-compat
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk
# dnsmasq-full is intentionally not a core dependency. Phase 0/T010 must
# establish whether a selected feature needs it before setup stages a swap.

# call BuildPackage - OpenWrt buildroot signature
