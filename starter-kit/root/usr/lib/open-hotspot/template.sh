#!/bin/sh
# template.sh — allow-listed local portal template installer.
#
# openNDS uses ThemeSpec for its built-in splash sequence. This manager's
# credential page is a local FAS page, so templates are intentionally kept as
# local, static HTML wrappers and are never downloaded from a URL.

set -eu

TEMPLATE_ROOT=${OPEN_HOTSPOT_TEMPLATE_ROOT:-/usr/share/open-hotspot/templates}
PORTAL_DIR=${OPEN_HOTSPOT_PORTAL_DIR:-/etc/open-hotspot}
PORTAL_FILE=${OPEN_HOTSPOT_PORTAL_FILE:-$PORTAL_DIR/portal.html}

template_path() {
	case "$1" in
		english|arabic-rtl) printf '%s/%s.html\n' "$TEMPLATE_ROOT" "$1" ;;
		*) return 1 ;;
	esac
}

template_validate() {
	path=$(template_path "$1") || return 1
	[ -r "$path" ] || return 1
	for marker in '{{CSS_HREF}}' '{{PAGE_TITLE}}' '{{BRAND}}' '{{HEADING}}' '{{ALERT}}' '{{BODY}}'; do
		grep -F "$marker" "$path" >/dev/null || return 1
	done
	# Only the six markers above are interpreted by fas.php. Reject unknown
	# markers so a typo cannot silently produce a broken portal.
	unknown=$(sed -n 's/.*{{\([^}]*\)}}.*/\1/p' "$path" | sort -u)
	[ -z "$unknown" ] || {
		while IFS= read -r marker; do
			case "$marker" in CSS_HREF|PAGE_TITLE|BRAND|HEADING|ALERT|BODY) ;; *) return 1 ;; esac
		done <<EOF
$unknown
EOF
	}
}

template_apply() {
	template_validate "$1" || return 1
	path=$(template_path "$1")
	mkdir -p "$PORTAL_DIR"
	tmp=$(mktemp "$PORTAL_DIR/.portal.html.XXXXXX")
	trap 'rm -f "$tmp"' EXIT HUP INT TERM
	cp "$path" "$tmp"
	chmod 0644 "$tmp"
	mv "$tmp" "$PORTAL_FILE"
	trap - EXIT HUP INT TERM
}

case "${1:-}" in
	list)
		printf '%s\n' english arabic-rtl
		;;
	validate)
		[ "$#" -eq 2 ] || exit 2
		template_validate "$2"
		;;
	apply)
		[ "$#" -eq 2 ] || exit 2
		template_apply "$2"
		;;
	*)
		echo 'usage: template.sh {list|validate|apply} [english|arabic-rtl]' >&2
		exit 2
		;;
esac
