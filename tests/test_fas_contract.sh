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

run_fas() {
	OPEN_HOTSPOT_FAS_SCRIPT="$root/starter-kit/root/www/nds/fas.php" \
	QUERY_STRING="fas=$encoded" \
	REQUEST_METHOD="${REQUEST_METHOD:-GET}" \
	OH_BODY="${OH_BODY:-}" \
	php -r 'parse_str(getenv("QUERY_STRING") ?: "", $_GET); parse_str(getenv("OH_BODY") ?: "", $_POST); $_SERVER["REQUEST_METHOD"] = getenv("REQUEST_METHOD") ?: "GET"; $_SERVER["SCRIPT_NAME"] = "/nds/fas.php"; require getenv("OPEN_HOTSPOT_FAS_SCRIPT");'
}

wrong=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=999999&fas=$encoded" run_fas)
printf '%s' "$wrong" | grep -F 'بيانات الدخول غير صحيحة.' >/dev/null

success=$(REQUEST_METHOD=POST OH_BODY="username=ahmed&pin=123456&fas=$encoded" run_fas)
printf '%s' "$success" | grep -F '/opennds_auth/' >/dev/null
printf '%s' "$success" | grep -Eq 'name="custom" value="[0-9a-f]{32}"'

python3 - "$OPEN_HOTSPOT_DB_PATH" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
row = connection.execute(
    "SELECT device_mac,state,length(auth_key) FROM auth_transactions"
).fetchone()
assert row == ("AA:BB:CC:DD:EE:FF", "pending", 32), row
PY
