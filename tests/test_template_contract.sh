#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
template="$root/starter-kit/root/usr/lib/open-hotspot/template.sh"
template_root="$root/starter-kit/root/usr/share/open-hotspot/templates"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sh -n "$template"
[ "$(OPEN_HOTSPOT_TEMPLATE_ROOT="$template_root" sh "$template" list)" = "english
arabic-rtl" ]
OPEN_HOTSPOT_TEMPLATE_ROOT="$template_root" sh "$template" validate english
OPEN_HOTSPOT_TEMPLATE_ROOT="$template_root" sh "$template" validate arabic-rtl
OPEN_HOTSPOT_TEMPLATE_ROOT="$template_root" \
	OPEN_HOTSPOT_PORTAL_DIR="$tmp/etc/open-hotspot" \
	OPEN_HOTSPOT_PORTAL_FILE="$tmp/etc/open-hotspot/portal.html" \
	sh "$template" apply arabic-rtl
grep -F '{{BODY}}' "$tmp/etc/open-hotspot/portal.html" >/dev/null
! OPEN_HOTSPOT_TEMPLATE_ROOT="$template_root" sh "$template" validate unknown
