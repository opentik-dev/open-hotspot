#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
command -v php >/dev/null 2>&1 || {
	echo 'SKIP: php is not installed on the host'
	exit 0
}
php -r 'exit(in_array("sqlite", PDO::getAvailableDrivers(), true) ? 0 : 1);' 2>/dev/null || {
	echo 'SKIP: PHP PDO SQLite is not installed on the host'
	exit 0
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_HOTSPOT_DB_PATH="$tmp/hotspot.db"
export OPEN_HOTSPOT_SCHEMA_PATH="$root/starter-kit/root/usr/lib/open-hotspot/schema.sql"
export OPEN_HOTSPOT_PHP_BIN=php
export OPEN_HOTSPOT_PBKDF2_HELPER="$root/starter-kit/root/usr/lib/open-hotspot/pbkdf2.php"
export OPEN_HOTSPOT_KDF_PATH="$root/starter-kit/root/usr/lib/open-hotspot/kdf.php"
export OPEN_HOTSPOT_TEMPLATE_ROOT="$root/starter-kit/root/usr/share/open-hotspot/templates"
export OPEN_HOTSPOT_FAS_KEY='test-fas-key'

. "$root/starter-kit/root/usr/lib/open-hotspot/pbkdf2.sh"
stored=$(pw_hash '123456' 5000)
salt=$(printf '%s' "$stored" | cut -d: -f2)
hash=$(printf '%s' "$stored" | cut -d: -f4)

python3 - "$OPEN_HOTSPOT_DB_PATH" "$OPEN_HOTSPOT_SCHEMA_PATH" "$salt" "$hash" <<'PY'
import sqlite3
import sys

db, schema, salt, digest = sys.argv[1:]
connection = sqlite3.connect(db)
connection.executescript(open(schema, encoding="utf-8").read())
connection.execute(
    "INSERT INTO accounts(username,pin_hash,pin_salt,pin_iter,profile_id) "
    "VALUES (?,?,?,?,1)",
    ("ahmed", digest, salt, 5000),
)
connection.commit()
connection.close()
PY

encoded=$(python3 - <<'PY'
import base64
import urllib.parse

payload = (
    'clientip=192.168.70.20, '
    'clientmac=AA:BB:CC:DD:EE:FF, '
    'gatewayname=Open-HotSpot, '
    'hid=test-hid, '
    'gatewayaddress=192.168.70.1:2050, '
    'authdir=opennds_auth, '
    'originurl=http%3A%2F%2Fexample.test%2F, '
    'clientif=br-lan'
)
print(urllib.parse.quote(base64.b64encode(payload.encode()).decode(), safe=''))
PY
)

encoded_client_hid=$(python3 - <<'PY'
import base64
import urllib.parse

payload = (
    'clientip=192.168.70.21, '
    'clientmac=11:22:33:44:55:66, '
    'gatewayname=Open-HotSpot, '
    'client_hid=compat-hid, '
    'gatewayaddress=192.168.70.1:2050, '
    'authdir=opennds_auth, '
    'originurl=http%3A%2F%2Fexample.test%2F, '
    'clientif=br-lan'
)
print(urllib.parse.quote(base64.b64encode(payload.encode()).decode(), safe=''))
PY
)

encoded_cpd_login=$(python3 - <<'PY'
import base64
import urllib.parse

payload = (
    'hid=cpd-hid, '
    'clientip=192.168.70.22, '
    'clientmac=22:33:44:55:66:77, '
    'client_type=cpd_url, '
    'cpd_query=http%3A%2F%2Fstatus.client%2Flogin, '
    'gatewayname=Open-HotSpot, '
    'gatewayurl=http%3A%2F%2Fstatus.client, '
    'version=10.3.1, '
    'gatewayaddress=192.168.70.1:2050, '
    'gatewaymac=3023036dab4d, '
    'originurl=http%3A%2F%2Fstatus.client%2Flogin, '
    'clientif=br-lan, themespec='
)
print(urllib.parse.quote(base64.b64encode(payload.encode()).decode(), safe=''))
PY
)

run_fas() {
	OPEN_HOTSPOT_FAS_SCRIPT="$root/starter-kit/root/www/nds/fas.php" \
	QUERY_STRING="${OH_QUERY-fas=$encoded}" \
	REQUEST_METHOD="${REQUEST_METHOD:-GET}" \
	OH_BODY="${OH_BODY:-}" \
	php -r 'parse_str(getenv("QUERY_STRING") ?: "", $_GET); parse_str(getenv("OH_BODY") ?: "", $_POST); $_SERVER["REQUEST_METHOD"] = getenv("REQUEST_METHOD") ?: "GET"; $_SERVER["SCRIPT_NAME"] = "/nds/fas.php"; require getenv("OPEN_HOTSPOT_FAS_SCRIPT");'
}

wrong=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=999999&fas=$encoded" run_fas)
printf '%s' "$wrong" | grep -F 'بيانات الدخول غير صحيحة.' >/dev/null

success=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=123456&fas=$encoded" run_fas)
printf '%s' "$success" | grep -F '/opennds_auth/' >/dev/null
printf '%s' "$success" | grep -Eq 'name="custom" value="[0-9a-f]{32}"'

compat=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=123456&fas=$encoded_client_hid" run_fas)
printf '%s' "$compat" | grep -F '/opennds_auth/' >/dev/null
printf '%s' "$compat" | grep -Eq 'name="custom" value="[0-9a-f]{32}"'

cpd=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=123456&fas=$encoded_cpd_login" run_fas)
printf '%s' "$cpd" | grep -F '/opennds_auth/' >/dev/null
printf '%s' "$cpd" | grep -Eq 'name="custom" value="[0-9a-f]{32}"'

voucher_code=ABCDEF0123456789ABCD
python3 - "$OPEN_HOTSPOT_DB_PATH" "$voucher_code" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute(
    "INSERT INTO vouchers(code,profile_id,validity_seconds) VALUES (?,?,?)",
    (sys.argv[2], 1, 3600),
)
connection.commit()
connection.close()
PY

voucher=$(REQUEST_METHOD=POST OH_BODY="username=fromvoucher&pin=7890&voucher=$voucher_code&fas=$encoded" run_fas)
printf '%s' "$voucher" | grep -F '/opennds_auth/' >/dev/null
printf '%s' "$voucher" | grep -Eq 'name="custom" value="[0-9a-f]{32}"'

python3 - "$OPEN_HOTSPOT_DB_PATH" "$voucher_code" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
status, username = connection.execute(
    "SELECT v.status, a.username FROM vouchers v JOIN accounts a ON a.id=v.redeemed_by WHERE v.code=?",
    (sys.argv[2],),
).fetchone()
assert (status, username) == ("redeemed", "fromvoucher"), (status, username)
PY

python3 - "$OPEN_HOTSPOT_DB_PATH" "$salt" "$hash" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
salt, digest = sys.argv[2:]
connection.execute(
    "INSERT INTO profiles(name,period_type,time_limit_s) VALUES (?,?,?)",
    ("exhausted-test", "none", 60),
)
profile_id = connection.execute(
    "SELECT id FROM profiles WHERE name='exhausted-test'"
).fetchone()[0]
connection.executemany(
    "INSERT INTO accounts(username,pin_hash,pin_salt,pin_iter,profile_id,status,expires_at) "
    "VALUES (?,?,?,?,?,?,?)",
    [
        ("expired", digest, salt, 5000, 1, "active", "2000-01-01T00:00:00Z"),
        ("suspended", digest, salt, 5000, 1, "suspended", None),
        ("exhausted", digest, salt, 5000, profile_id, "active", None),
    ],
)
exhausted_id = connection.execute(
    "SELECT id FROM accounts WHERE username='exhausted'"
).fetchone()[0]
connection.execute(
    "INSERT INTO usage_periods(account_id,period_start,period_end,seconds_used) "
    "VALUES (?,?,?,?)",
    (exhausted_id, "1970-01-01T00:00:00Z", "9999-12-31T23:59:59Z", 60),
)
connection.commit()
PY

for username in expired suspended exhausted; do
	negative=$(REQUEST_METHOD=POST OH_BODY="username=$username&pin=123456&fas=$encoded" run_fas)
	! printf '%s' "$negative" | grep -F '/opennds_auth/' >/dev/null
done

for attempt in 1 2 3 4 5; do
	bad=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=999999&fas=$encoded" run_fas)
	printf '%s' "$bad" | grep -F 'بيانات الدخول غير صحيحة.' >/dev/null
done
locked=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=123456&fas=$encoded" run_fas)
! printf '%s' "$locked" | grep -F '/opennds_auth/' >/dev/null

missing=$(REQUEST_METHOD=GET OH_QUERY='' OH_BODY='' run_fas || true)
printf '%s' "$missing" | grep -F 'بيانات FAS الناقصة.' >/dev/null
printf '%s' "$missing" | grep -F 'http://status.client' >/dev/null
printf '%s' "$missing" | grep -F 'open-hotspot-fas.css' >/dev/null

python3 - "$OPEN_HOTSPOT_DB_PATH" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
row = connection.execute(
    "SELECT device_mac,state,length(auth_key) FROM auth_transactions"
).fetchone()
assert row == ("AA:BB:CC:DD:EE:FF", "pending", 32), row
PY
