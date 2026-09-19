#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/starter-kit/root/usr/lib/open-hotspot/quota.sh"

[ "$(quota_remaining 7200 1800 500 100 1000 250)" = "5400|400|750|0" ]
[ "$(quota_remaining 0 999 0 999 0 999)" = "0|0|0|0" ]
[ "$(quota_remaining 60 60 0 0 100 99)" = "0|0|1|1" ]
if quota_remaining 60 bad 0 0 0 0 >/dev/null 2>&1; then
	echo "quota accepted invalid input" >&2
	exit 1
fi
