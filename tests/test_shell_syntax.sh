#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
find "$root/starter-kit/root" -type f \( -name '*.sh' -o -path '*/cgi-bin/*' \) -exec sh -n {} \;
