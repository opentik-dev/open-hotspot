#!/bin/sh
set -eu

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
PLAN="$PROJECT/specs/001-open-hotspot/plan.md"

for entry in \
	"starter-kit/root/usr/lib/open-hotspot/session-restore.sh" \
	"starter-kit/root/usr/lib/open-hotspot/diagnose.sh" \
	"starter-kit/root/usr/lib/open-hotspot/backup.sh" \
	"starter-kit/root/usr/lib/open-hotspot/adapters/opennds-v11.0.0.sh" \
	"starter-kit/luasrc/view/open-hotspot/accounts.htm" \
	"starter-kit/luasrc/view/open-hotspot/dev.htm"; do
	test -f "$PROJECT/$entry"
done

grep -F 'session-restore.sh' "$PLAN" >/dev/null
grep -F 'server-rendered RPC-backed pages' "$PLAN" >/dev/null
if grep -F '│   └── validate.sh' "$PLAN" >/dev/null; then
	printf '%s\n' 'legacy validate.sh remains in package-layout plan' >&2
	exit 1
fi

printf '%s\n' 'package-layout-contract-ok'
