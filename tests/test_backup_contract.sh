#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
backup="$root/starter-kit/root/usr/lib/open-hotspot/backup.sh"
sh -n "$backup"
grep -F 'backup_validate' "$backup" >/dev/null
grep -F 'PRAGMA integrity_check' "$backup" >/dev/null
grep -F 'rollback=' "$backup" >/dev/null
grep -F 'umask 077' "$backup" >/dev/null
grep -F 'chmod 600' "$backup" >/dev/null
grep -F 'sort -u' "$backup" >/dev/null
db="$root/starter-kit/root/usr/lib/open-hotspot/db.sh"
grep -F 'chmod 600' "$db" >/dev/null
! grep -Eq 'ndsctl|opennds[[:space:]]+(auth|deauth)' "$backup"
