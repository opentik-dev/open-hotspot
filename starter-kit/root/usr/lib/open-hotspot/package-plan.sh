#!/bin/sh
# package-plan.sh — verified core package plan for a clean OpenWrt target.
#
# This is deliberately data-only. Package installation belongs to the setup
# wizard/administrator and must never silently replace dnsmasq.

open_hotspot_package_plan() {
	cat <<'EOF'
opennds
sqlite3-cli
php8-cgi
php8-mod-pdo-sqlite
luci-base
luci-compat
EOF
}

if [ "${OPEN_HOTSPOT_PACKAGE_PLAN_EXEC:-0}" = 1 ]; then
	open_hotspot_package_plan
fi
