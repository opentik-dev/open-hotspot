#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CSS="$ROOT/starter-kit/root/www/luci-static/resources/open-hotspot.css"
ACCOUNTS="$ROOT/starter-kit/luasrc/view/open-hotspot/accounts.htm"
DEVICES="$ROOT/starter-kit/luasrc/view/open-hotspot/devices.htm"

grep -F '.oh-action-row' "$CSS" >/dev/null
grep -F '.oh-page button' "$CSS" >/dev/null
grep -F 'open-hotspot.css' "$ROOT/starter-kit/luasrc/view/open-hotspot/events.htm" >/dev/null
grep -F 'open-hotspot.css' "$ROOT/starter-kit/luasrc/view/open-hotspot/dev.htm" >/dev/null
grep -F '<div class="oh-action-row">' "$ACCOUNTS" >/dev/null
grep -F '<div class="oh-action-row">' "$DEVICES" >/dev/null

echo "PASS: shared button and action-row layout contract"
