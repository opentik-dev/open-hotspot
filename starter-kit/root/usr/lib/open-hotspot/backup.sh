#!/bin/sh
# backup.sh — validated local backup/export/import for the manager state.
#
# Archives contain the SQLite database and open-hotspot UCI configuration only.
# Import validates the archive first, creates a rollback archive, then replaces
# both files atomically enough for the small local manager state.

set -eu

. "${OPEN_HOTSPOT_DB_HELPER:-/usr/lib/open-hotspot/db.sh}"

BACKUP_CONFIG="${OPEN_HOTSPOT_CONFIG_PATH:-/etc/config/open-hotspot}"
BACKUP_DIR="${OPEN_HOTSPOT_BACKUP_DIR:-/tmp}"

_backup_archive() {
	case "$1" in
		/*) : ;;
		*) return 1 ;;
	esac
	case "$1" in *..*|*[!A-Za-z0-9_./:-]*) return 1 ;; esac
	[ -f "$1" ]
}

_backup_validate_members() {
	list="$1"
	while IFS= read -r member; do
		case "$member" in
			hotspot.db|open-hotspot) ;;
			*) return 1 ;;
		esac
	done <<EOF
$list
EOF
	printf '%s\n' "$list" | grep -Fx hotspot.db >/dev/null
	printf '%s\n' "$list" | grep -Fx open-hotspot >/dev/null
}

backup_validate() {
	archive="$1"
	_backup_archive "$archive" || return 1
	tmp=$(mktemp -d "${BACKUP_DIR%/}/open-hotspot-validate.XXXXXX")
	trap 'rm -rf "$tmp"' EXIT
	list=$(tar -tzf "$archive") || return 1
	_backup_validate_members "$list" || return 1
	tar -xzf "$archive" -C "$tmp"
	[ -f "$tmp/hotspot.db" ] && [ -f "$tmp/open-hotspot" ] || return 1
	[ "$(sqlite3 -batch "$tmp/hotspot.db" 'PRAGMA integrity_check;')" = 'ok' ] || return 1
	version=$(sqlite3 -batch "$tmp/hotspot.db" 'SELECT max(version) FROM schema_meta;' 2>/dev/null || true)
	[ "$version" = "$DB_SCHEMA_VERSION" ] || return 1
	grep -Eq "^[[:space:]]*config[[:space:]]+manager[[:space:]]+'global'" "$tmp/open-hotspot" || return 1
	printf 'valid\n'
}

backup_export() {
	archive="${1:-${BACKUP_DIR%/}/open-hotspot-backup-$(date -u +%Y%m%dT%H%M%SZ).tar.gz}"
	case "$archive" in *..*|*[!A-Za-z0-9_./:-]*) return 1 ;; esac
	tmp=$(mktemp -d "${BACKUP_DIR%/}/open-hotspot-export.XXXXXX")
	trap 'rm -rf "$tmp"' EXIT
	db_init
	sqlite3 -batch "$DB_PATH" ".backup '$tmp/hotspot.db'"
	cp "$BACKUP_CONFIG" "$tmp/open-hotspot"
	tar -czf "$archive" -C "$tmp" hotspot.db open-hotspot
	printf '%s\n' "$archive"
}

backup_import() {
	archive="$1"
	backup_validate "$archive" >/dev/null
	rollback="${BACKUP_DIR%/}/open-hotspot-before-import-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
	backup_export "$rollback" >/dev/null
	tmp=$(mktemp -d "${BACKUP_DIR%/}/open-hotspot-import.XXXXXX")
	trap 'rm -rf "$tmp"' EXIT
	tar -xzf "$archive" -C "$tmp"
	mkdir -p "$(dirname "$DB_PATH")" "$(dirname "$BACKUP_CONFIG")"
	cp "$tmp/hotspot.db" "${DB_PATH}.import"
	cp "$tmp/open-hotspot" "${BACKUP_CONFIG}.import"
	mv "${DB_PATH}.import" "$DB_PATH"
	mv "${BACKUP_CONFIG}.import" "$BACKUP_CONFIG"
	printf 'imported rollback=%s\n' "$rollback"
}

case "${1:-}" in
	export) shift; backup_export "${1:-}" ;;
	validate) shift; backup_validate "$1" ;;
	import) shift; backup_import "$1" ;;
	*) echo 'usage: backup.sh {export [archive]|validate archive|import archive}' >&2; exit 2 ;;
esac
