#!/bin/sh
set -eu

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

python3 "$PROJECT/tools/check-acceptance-state.py" --project "$PROJECT"

if python3 "$PROJECT/tools/check-acceptance-state.py" --project "$PROJECT" --release; then
	printf '%s\n' 'FAIL: unpublished candidate unexpectedly passed production release gates' >&2
	exit 1
fi

printf '%s\n' 'acceptance-state-contract-ok'
