#!/bin/sh
set -eu

state=${MOCK_UCI_STATE:?MOCK_UCI_STATE is required}
mkdir -p "$(dirname "$state")"

[ "${1:-}" = '-q' ] && shift
command_name=${1:-}
shift

case "$command_name" in
	get)
		path=${1:?missing path}
		key=${path##*.}
		[ -f "$state" ] || exit 1
		awk -F= -v wanted="$key" '
			$1 == wanted { value=substr($0, index($0, "=") + 1); found=1 }
			END { if (found) print value; else exit 1 }
		' "$state"
		;;
	show)
		[ -f "$state" ] || exit 1
		while IFS= read -r entry; do
			key=${entry%%=*}
			value=${entry#*=}
			printf 'open-hotspot.global.%s=%s\n' "$key" "$value"
		done < "$state"
		;;
	set)
		assignment=${1:?missing assignment}
		path=${assignment%%=*}
		value=${assignment#*=}
		key=${path##*.}
		tmp="$state.tmp"
		if [ -f "$state" ]; then
			awk -F= -v wanted="$key" '$1 != wanted' "$state" > "$tmp"
		fi
		printf '%s=%s\n' "$key" "$value" >> "$tmp"
		mv "$tmp" "$state"
		;;
	commit)
		exit 0
		;;
	*)
		echo "unsupported mock uci operation: $command_name" >&2
		exit 2
		;;
esac
