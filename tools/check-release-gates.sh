#!/bin/sh
set -eu

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TASKS="$PROJECT/specs/001-open-hotspot/tasks.md"

failed=0
for gate in T003 T006 T011 T012 T052 T086 T087 T088 T090; do
	if ! grep -Eq "^- \[x\] \*\*${gate}( |$)" "$TASKS"; then
		printf 'release-gate-open: %s\n' "$gate" >&2
		failed=1
	fi
done

if [ "$failed" -ne 0 ]; then
	printf '%s\n' 'release-blocked: close every required physical-acceptance gate before tagging' >&2
	exit 1
fi

printf '%s\n' 'release-gates-closed'
