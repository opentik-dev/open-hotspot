#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fas="$root/starter-kit/root/www/nds/fas.php"
binauth="$root/starter-kit/root/usr/lib/open-hotspot/binauth.sh"
custom="$root/starter-kit/root/usr/lib/open-hotspot/custombinauth.sh"
db="$root/starter-kit/root/usr/lib/open-hotspot/db.sh"

grep -F 'prepare(' "$fas" >/dev/null
grep -F 'preg_match' "$fas" >/dev/null
grep -F 'OPEN_HOTSPOT_DB_PATH' "$fas" >/dev/null
! grep -Eq '(^|[[:space:]])ndsctl[[:space:]]' "$binauth"
! grep -Eq '(^|[[:space:]])ndsctl[[:space:]]' "$custom"
! grep -Eq 'logger[^\n]*pin|syslog[^\n]*pin|db_log_event[^\n]*pin' "$fas" "$binauth" "$custom"
grep -F "sqlite3 -cmd '.timeout 5000'" "$db" >/dev/null
grep -F 'BEGIN IMMEDIATE' "$db" >/dev/null
! grep -REq 'echo[[:space:]].*\$pin|logger.*\$pin' starter-kit/root/usr/lib/open-hotspot starter-kit/root/www/nds
