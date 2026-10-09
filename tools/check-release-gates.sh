#!/bin/sh
set -eu

PROJECT=${PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

# A task checkbox is a human-readable projection of acceptance state, not the
# release authority. The checker rejects any disagreement before considering a
# production release.
exec python3 "$PROJECT/tools/check-acceptance-state.py" --project "$PROJECT" --release
