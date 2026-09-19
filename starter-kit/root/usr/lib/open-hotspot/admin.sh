#!/bin/sh
# admin.sh — bounded local database operations for the LuCI/RPC boundary.
#
# Numeric and identifier fields are allow-listed. Free text is SQL-escaped
# because sqlite3-cli has no prepared-statement API here. PINs are read from
# stdin and are never accepted as command-line arguments.

set -eu

. "${OPEN_HOTSPOT_DB_HELPER:-/usr/lib/open-hotspot/db.sh}"
. "${OPEN_HOTSPOT_PBKDF2_HELPER_SH:-/usr/lib/open-hotspot/pbkdf2.sh}"

OPEN_HOTSPOT_NDS_HELPER="${OPEN_HOTSPOT_NDS_HELPER:-/usr/lib/open-hotspot/opennds.sh}"

_admin_period() {
	case "$1" in hourly|daily|monthly|yearly|none) return 0 ;; *) return 1 ;; esac
}

_admin_status() {
	case "$1" in active|suspended) return 0 ;; *) return 1 ;; esac
}

_admin_nonnegative() { _valid_int "$1"; }
_admin_positive() { _valid_int "$1" && [ "$1" -ge 1 ]; }
_admin_name() { _valid_ident "$1" && [ "${#1}" -le 64 ]; }
_admin_username() { _admin_name "$1"; }

_admin_expiry_sql() {
	case "$1" in
		'') printf 'NULL\n' ;;
		????-??-??T??:??:??Z) printf "'%s'\n" "$(_sql_escape "$1")" ;;
		*) return 1 ;;
	esac
}

_admin_pin_line() {
	pin=''
	IFS= read -r pin || return 1
	case "$pin" in ''|*[!0-9]*) return 1 ;; esac
	[ "${#pin}" -ge 4 ] && [ "${#pin}" -le 32 ] || return 1
	printf '%s' "$pin"
}

admin_profile_list() {
	sqlite3 -batch -noheader -separator "$(printf '\t')" "$DB_PATH" \
		'SELECT id,name,period_type,time_limit_s,upload_limit_b,download_limit_b,
		        upload_rate_kbps,download_rate_kbps,max_devices
		   FROM profiles ORDER BY id;'
}

admin_profile_create() {
	name="$1"; period="$2"; time_limit="$3"; upload_limit="$4"
	download_limit="$5"; upload_rate="$6"; download_rate="$7"; max_devices="$8"
	_admin_name "$name" || return 1
	_admin_period "$period" || return 1
	_admin_nonnegative "$time_limit" && _admin_nonnegative "$upload_limit" || return 1
	_admin_nonnegative "$download_limit" && _admin_nonnegative "$upload_rate" || return 1
	_admin_nonnegative "$download_rate" && _admin_positive "$max_devices" || return 1
	sqlite3 -batch "$DB_PATH" "PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;
	INSERT INTO profiles
	 (name,period_type,time_limit_s,upload_limit_b,download_limit_b,
	  upload_rate_kbps,download_rate_kbps,max_devices)
	 VALUES ('$(_sql_escape "$name")','$period',$time_limit,$upload_limit,
	         $download_limit,$upload_rate,$download_rate,$max_devices);
	SELECT last_insert_rowid(); COMMIT;"
}

admin_profile_update() {
	id="$1"; name="$2"; period="$3"; time_limit="$4"; upload_limit="$5"
	download_limit="$6"; upload_rate="$7"; download_rate="$8"; max_devices="$9"
	_valid_int "$id" || return 1
	_admin_name "$name" || return 1
	_admin_period "$period" || return 1
	_admin_nonnegative "$time_limit" && _admin_nonnegative "$upload_limit" || return 1
	_admin_nonnegative "$download_limit" && _admin_nonnegative "$upload_rate" || return 1
	_admin_nonnegative "$download_rate" && _admin_positive "$max_devices" || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE profiles SET name='$(_sql_escape "$name")', period_type='$period',
	 time_limit_s=$time_limit, upload_limit_b=$upload_limit,
	 download_limit_b=$download_limit, upload_rate_kbps=$upload_rate,
	 download_rate_kbps=$download_rate, max_devices=$max_devices,
	 updated_at=datetime('now') WHERE id=$id;
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

admin_profile_delete() {
	id="$1"; _valid_int "$id" || return 1
	[ "$id" -ne 1 ] || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	DELETE FROM profiles WHERE id=$id AND NOT EXISTS
	 (SELECT 1 FROM accounts WHERE profile_id=$id AND deleted_at IS NULL);
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

admin_account_list() {
	sqlite3 -batch -noheader -separator "$(printf '\t')" "$DB_PATH" \
		'SELECT a.id,a.username,a.profile_id,p.name,a.status,
		        COALESCE(a.expires_at,"")
		   FROM accounts a JOIN profiles p ON p.id=a.profile_id
		  WHERE a.deleted_at IS NULL ORDER BY a.username;'
}

admin_account_create() {
	username="$1"; profile_id="$2"; expires_at="${3:-}"
	_admin_username "$username" || return 1
	_valid_int "$profile_id" || return 1
	expires_sql=$(_admin_expiry_sql "$expires_at") || return 1
	iter=$(uci -q get open-hotspot.global.pin_iterations 2>/dev/null || printf '100000')
	_valid_int "$iter" && [ "$iter" -ge 1 ] || return 1
	pin=$(_admin_pin_line) || return 1
	stored=$(pw_hash "$pin" "$iter") || return 1
	salt=$(printf '%s' "$stored" | cut -d: -f2)
	hash=$(printf '%s' "$stored" | cut -d: -f4)
	[ "${#salt}" -eq 32 ] && [ "${#hash}" -eq 64 ] || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	INSERT INTO accounts(username,pin_hash,pin_salt,pin_iter,profile_id,expires_at)
	 SELECT '$(_sql_escape "$username")','$hash','$salt',$iter,$profile_id,$expires_sql
	 WHERE EXISTS (SELECT 1 FROM profiles WHERE id=$profile_id);
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

admin_account_update() {
	id="$1"; username="$2"; profile_id="$3"; status="$4"; expires_at="${5:-}"
	_valid_int "$id" || return 1
	_admin_username "$username" || return 1
	_valid_int "$profile_id" || return 1
	_admin_status "$status" || return 1
	expires_sql=$(_admin_expiry_sql "$expires_at") || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE accounts SET username='$(_sql_escape "$username")', profile_id=$profile_id,
	 status='$status', expires_at=$expires_sql, updated_at=datetime('now')
	 WHERE id=$id AND deleted_at IS NULL
	   AND EXISTS (SELECT 1 FROM profiles WHERE id=$profile_id);
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

# Renew starts a fresh quota window inside the current calendar period. The
# previous aggregate remains in usage_periods/history; renewed_at selects the
# new window for future authentication and accounting. Existing sessions are
# deauthenticated through the verified adapter and their close callbacks retain
# responsibility for final accounting.
admin_account_renew() {
	id="$1"; _valid_int "$id" || return 1
	macs=$(sqlite3 -batch -noheader "$DB_PATH" \
		"SELECT d.mac FROM devices d JOIN active_sessions s ON s.device_id=d.id
		  JOIN accounts a ON a.id=d.account_id
		 WHERE a.id=$id AND a.status='active' AND a.deleted_at IS NULL
		   AND s.state='active' ORDER BY d.mac;") || return 1
	for mac in $macs; do
		_valid_mac "$mac" || return 1
		"$OPEN_HOTSPOT_NDS_HELPER" deauth "$mac" || return 1
	done
	renewed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE accounts SET renewed_at='$(_sql_escape "$renewed_at")', updated_at=datetime('now')
	 WHERE id=$id AND status='active' AND deleted_at IS NULL;
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null || return 1
	db_log_event account_renew "$id" "$renewed_at" || true
}

admin_account_set_pin() {
	id="$1"; _valid_int "$id" || return 1
	iter=$(uci -q get open-hotspot.global.pin_iterations 2>/dev/null || printf '100000')
	_valid_int "$iter" && [ "$iter" -ge 1 ] || return 1
	pin=$(_admin_pin_line) || return 1
	stored=$(pw_hash "$pin" "$iter") || return 1
	salt=$(printf '%s' "$stored" | cut -d: -f2)
	hash=$(printf '%s' "$stored" | cut -d: -f4)
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE accounts SET pin_hash='$hash', pin_salt='$salt', pin_iter=$iter,
	 updated_at=datetime('now') WHERE id=$id AND deleted_at IS NULL;
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

admin_account_delete() {
	id="$1"; _valid_int "$id" || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE accounts SET status='suspended', deleted_at=datetime('now'),
	 updated_at=datetime('now') WHERE id=$id AND deleted_at IS NULL;
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

# Device removal is deliberately conservative. A device referenced by an
# active-session row or a usage event is part of the audit trail and cannot be
# physically removed; block it instead. This keeps historical accounting
# foreign keys valid. Blocking is reversible with device-unblock; a successful
# removal is intentionally irreversible.
admin_device_list() {
	# A visible separator preserves an empty last_seen field through POSIX
	# read/IFS parsing; tab is IFS whitespace and would collapse that field.
	sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		'SELECT d.id,d.account_id,a.username,d.mac,d.status,
		        d.first_seen,COALESCE(d.last_seen,""),
		        (SELECT count(*) FROM active_sessions s
		          WHERE s.device_id=d.id AND s.state="active")
		   FROM devices d JOIN accounts a ON a.id=d.account_id
		  WHERE a.deleted_at IS NULL
		  ORDER BY a.username,d.mac;'
}

admin_device_set_status() {
	id="$1"; status="$2"
	_valid_int "$id" || return 1
	case "$status" in blocked|active) ;; *) return 1 ;; esac
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE devices SET status='$status', updated_at=datetime('now') WHERE id=$id;
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

admin_device_remove() {
	id="$1"; _valid_int "$id" || return 1
	sqlite3 -batch "$DB_PATH" "PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;
	DELETE FROM devices
	 WHERE id=$id
	   AND NOT EXISTS (SELECT 1 FROM active_sessions WHERE device_id=$id)
	   AND NOT EXISTS (SELECT 1 FROM usage_events WHERE device_id=$id);
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

# MAC ownership is never changed by authentication. Reassignment is explicit,
# audited, and only allowed after the old live session has been observed closed.
admin_device_reassign() {
	id="$1"; target_account="$2"
	_valid_int "$id" && _valid_int "$target_account" || return 1
	row=$(sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		"SELECT account_id,mac,status FROM devices WHERE id=$id LIMIT 1;") || return 1
	[ -n "$row" ] || return 1
	old_ifs="$IFS"; IFS='|'
	read -r old_account mac status <<EOF
$row
EOF
	IFS="$old_ifs"
	_valid_int "$old_account" && _valid_mac "$mac" || return 1
	[ "$old_account" -ne "$target_account" ] || return 1
	[ "$status" = active ] || return 1
	[ "$(sqlite3 -batch -noheader "$DB_PATH" \
		"SELECT count(*) FROM active_sessions WHERE device_id=$id AND state='active';")" = 0 ] || return 1
	[ "$(sqlite3 -batch -noheader "$DB_PATH" \
		"SELECT count(*) FROM accounts WHERE id=$target_account AND status='active' AND deleted_at IS NULL;")" = 1 ] || return 1
	sqlite3 -batch "$DB_PATH" "BEGIN IMMEDIATE;
	UPDATE devices SET account_id=$target_account, updated_at=datetime('now')
	 WHERE id=$id AND account_id=$old_account AND status='active';
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null || return 1
	db_log_event device_reassign "$target_account" "$id:$mac:from=$old_account" || true
}

admin_device_force_deauth() {
	id="$1"; _valid_int "$id" || return 1
	row=$(sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		"SELECT account_id,mac FROM devices WHERE id=$id AND status='active' LIMIT 1;") || return 1
	[ -n "$row" ] || return 1
	old_ifs="$IFS"
	IFS='|'
	read -r account_id mac <<EOF
$row
EOF
	IFS="$old_ifs"
	_valid_int "$account_id" && _valid_mac "$mac" || return 1
	"$OPEN_HOTSPOT_NDS_HELPER" deauth "$mac" || return 1
	# BinAuth remains responsible for session-close accounting. This records the
	# administrative request without changing live-session state locally.
	db_log_event force_deauth "$account_id" "$mac" || true
}

_voucher_code() {
	code=$(hexdump -v -n 10 -e '1/1 "%02X"' /dev/urandom 2>/dev/null) || return 1
	[ "${#code}" -eq 20 ] || return 1
	printf '%s\n' "$code"
}

admin_voucher_list() {
	sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		'SELECT v.id,v.code,v.profile_id,p.name,v.validity_seconds,v.status,
		        COALESCE(v.redeemed_by,""),COALESCE(v.redeemed_at,""),
		        COALESCE(v.expires_at,"")
		   FROM vouchers v JOIN profiles p ON p.id=v.profile_id
		  ORDER BY v.id DESC;'
}

admin_voucher_generate() {
	count="$1"; profile_id="$2"; validity_seconds="$3"
	_valid_int "$count" && [ "$count" -ge 1 ] && [ "$count" -le 1000 ] || return 1
	_valid_int "$profile_id" || return 1
	_valid_int "$validity_seconds" && [ "$validity_seconds" -ge 1 ] || return 1

	codes=''
	codes_sql=''
	values_sql=''
	i=0
	while [ "$i" -lt "$count" ]; do
		code=$(_voucher_code) || return 1
		codes="$codes $code"
		if [ -n "$codes_sql" ]; then codes_sql="$codes_sql,"; fi
		codes_sql="$codes_sql'$code'"
		if [ -n "$values_sql" ]; then values_sql="$values_sql,"; fi
		values_sql="$values_sql('$code',$profile_id,$validity_seconds)"
		i=$((i + 1))
	done

	result=$(sqlite3 -batch "$DB_PATH" "PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;
	INSERT INTO vouchers(code,profile_id,validity_seconds) VALUES $values_sql;
	SELECT count(*) FROM vouchers WHERE code IN ($codes_sql);
	COMMIT;" 2>/dev/null) || return 1
	[ "$(printf '%s\n' "$result" | tail -n 1)" = "$count" ] || return 1
	printf '%s\n' $codes
}

admin_voucher_revoke() {
	id="$1"; _valid_int "$id" || return 1
	sqlite3 -batch "$DB_PATH" "PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;
	UPDATE vouchers SET status='revoked'
	 WHERE id=$id AND status='unused';
	SELECT changes(); COMMIT;" | tail -n 1 | grep -Fx 1 >/dev/null
}

admin_overview() {
	# Keep the persistent dashboard query bounded and machine-readable. Live
	# openNDS state is fetched separately by rpcd through opennds.sh so this
	# database layer remains the source of truth for accounting.
	sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		'SELECT
		 (SELECT count(*) FROM accounts WHERE status="active" AND deleted_at IS NULL),
		 (SELECT count(*) FROM active_sessions WHERE state="active"),
		 COALESCE((SELECT sum(seconds_used) FROM usage_periods),0),
		 COALESCE((SELECT sum(bytes_up) FROM usage_periods),0),
		 COALESCE((SELECT sum(bytes_down) FROM usage_periods),0);'
}

admin_account_status_list() {
	. "${OPEN_HOTSPOT_PERIOD_HELPER:-/usr/lib/open-hotspot/period.sh}"
	. "${OPEN_HOTSPOT_QUOTA_HELPER:-/usr/lib/open-hotspot/quota.sh}"
	now=$(date +%s) || return 1
	rows=$(sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		'SELECT a.id,a.username,p.period_type,p.time_limit_s,
		        p.upload_limit_b,p.download_limit_b,COALESCE(a.renewed_at,"")
		   FROM accounts a JOIN profiles p ON p.id=a.profile_id
		  WHERE a.deleted_at IS NULL
		  ORDER BY a.username;') || return 1

	old_ifs="$IFS"
	while IFS='|' read -r id username period_type time_limit upload_limit download_limit renewed_at; do
		[ -n "$id" ] || continue
		window=$(period_window_effective "$period_type" "$renewed_at" "$now") || return 1
		period_start=$(printf '%s' "$window" | cut -f1)
		period_end=$(printf '%s' "$window" | cut -f2)
		usage=$(sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
			"SELECT COALESCE(seconds_used,0),COALESCE(bytes_up,0),COALESCE(bytes_down,0)
			   FROM usage_periods
			  WHERE account_id=$id AND period_start='$(_sql_escape "$period_start")'
			  LIMIT 1;") || return 1
		[ -n "$usage" ] || usage='0|0|0'
		IFS='|'
		read -r used_s used_up used_down <<EOF
$usage
EOF
		IFS="$old_ifs"
		remaining=$(quota_remaining "${time_limit:-0}" "${used_s:-0}" \
			"${upload_limit:-0}" "${used_up:-0}" \
			"${download_limit:-0}" "${used_down:-0}") || return 1
		IFS='|'
		read -r remaining_s remaining_up remaining_down exhausted <<EOF
$remaining
EOF
		IFS="$old_ifs"
		active_devices=$(sqlite3 -batch -noheader "$DB_PATH" \
			"SELECT count(*) FROM active_sessions WHERE account_id=$id AND state='active';") || return 1
		printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
			"$id" "$username" "$period_type" "$period_start" "$period_end" \
			"${time_limit:-0}" "${used_s:-0}" "${remaining_s:-0}" \
			"${upload_limit:-0}" "${used_up:-0}" "${remaining_up:-0}" \
			"${download_limit:-0}" "${used_down:-0}" "${remaining_down:-0}" \
			"${active_devices:-0}"
	done <<EOF
$rows
EOF
	IFS="$old_ifs"
}

admin_history_list() {
	# History is read-only and intentionally excludes pin material and auth
	# transaction payloads. The output is ordered newest-first for LuCI.
	sqlite3 -batch -noheader -separator '|' "$DB_PATH" \
		'SELECT u.account_id,a.username,u.period_start,u.period_end,
		        u.seconds_used,u.bytes_up,u.bytes_down,u.closed
		   FROM usage_periods u JOIN accounts a ON a.id=u.account_id
		  WHERE a.deleted_at IS NULL
		  ORDER BY u.period_start DESC,a.username
		  LIMIT 500;'
}

case "${1:-}" in
	profile-list) admin_profile_list ;;
	profile-create) shift; admin_profile_create "$@" ;;
	profile-update) shift; admin_profile_update "$@" ;;
	profile-delete) shift; admin_profile_delete "$@" ;;
	account-list) admin_account_list ;;
	account-create) shift; admin_account_create "$@" ;;
	account-update) shift; admin_account_update "$@" ;;
	account-renew) shift; admin_account_renew "$1" ;;
	account-set-pin) shift; admin_account_set_pin "$@" ;;
	account-delete) shift; admin_account_delete "$@" ;;
	device-list) admin_device_list ;;
	device-block) shift; admin_device_set_status "$1" blocked ;;
	device-unblock) shift; admin_device_set_status "$1" active ;;
	device-remove) shift; admin_device_remove "$1" ;;
	device-reassign) shift; admin_device_reassign "$1" "$2" ;;
	device-force-deauth) shift; admin_device_force_deauth "$1" ;;
	voucher-list) admin_voucher_list ;;
	voucher-generate) shift; admin_voucher_generate "$@" ;;
	voucher-revoke) shift; admin_voucher_revoke "$1" ;;
	overview) admin_overview ;;
	account-status-list) admin_account_status_list ;;
	history-list) admin_history_list ;;
	*) echo 'usage: admin.sh {profile|account|device|voucher}-{list|create|update|delete|block|unblock|remove|generate|revoke}|overview|history-list' >&2; exit 2 ;;
esac
