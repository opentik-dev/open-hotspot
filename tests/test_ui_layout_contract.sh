#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CSS="$ROOT/starter-kit/root/www/luci-static/resources/open-hotspot.css"
ACCOUNTS="$ROOT/starter-kit/luasrc/view/open-hotspot/accounts.htm"
PROFILES="$ROOT/starter-kit/luasrc/view/open-hotspot/profiles.htm"
DEVICES="$ROOT/starter-kit/luasrc/view/open-hotspot/devices.htm"

grep -F '.oh-action-row' "$CSS" >/dev/null
grep -F '.oh-page button' "$CSS" >/dev/null
grep -F '.oh-create-card' "$CSS" >/dev/null
grep -F '.oh-account-card' "$CSS" >/dev/null
grep -F '.oh-profile-card' "$CSS" >/dev/null
grep -F 'open-hotspot.css' "$ROOT/starter-kit/luasrc/view/open-hotspot/events.htm" >/dev/null
grep -F 'open-hotspot.css' "$ROOT/starter-kit/luasrc/view/open-hotspot/dev.htm" >/dev/null
grep -F 'oh-create-card' "$ACCOUNTS" >/dev/null
grep -F 'oh-create-card' "$PROFILES" >/dev/null
grep -F 'oh-account-card' "$ACCOUNTS" >/dev/null
grep -F 'oh-profile-card' "$PROFILES" >/dev/null
grep -F 'oh-profile-table' "$PROFILES" >/dev/null
grep -F '<div class="oh-action-row">' "$ACCOUNTS" >/dev/null
grep -F '<div class="oh-action-row">' "$DEVICES" >/dev/null

echo "PASS: shared button and action-row layout contract"
