#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$ROOT/starter-kit/root/usr/lib/open-hotspot/legacy-import.sh"
php="$ROOT/starter-kit/root/usr/lib/open-hotspot/legacy-import.php"
grep -q -- '--dry-run' "$script"
grep -q -- '--confirm-legacy-import' "$script"
grep -q 'OPEN_HOTSPOT_LEGACY_IMPORT_CONFIRM=YES' "$script"
grep -q 'PRAGMA query_only=ON' "$php"
grep -q 'hash_pbkdf2' "$php"
grep -q 'legacy database was not changed' "$php"
grep -q 'active_sessions' "$ROOT/starter-kit/root/usr/lib/open-hotspot/schema.sql"
echo legacy-import-contract-ok
