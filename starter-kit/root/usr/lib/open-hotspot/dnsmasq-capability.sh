#!/bin/sh
# dnsmasq-capability.sh — verify the openNDS dnsmasq feature boundary.
#
# The core Open-HotSpot flow (local FAS, BinAuth, SQLite accounting) does not
# need dnsmasq-full. openNDS autonomous blocklists/walled gardens do. This
# helper makes that distinction executable and never removes dnsmasq blindly.

set -eu

action=${1:-check}
uci_bin=${OPEN_HOTSPOT_UCI_BIN:-uci}

feature_requested() {
	"$uci_bin" -q show opennds 2>/dev/null |
		grep -E '\.(walledgarden|blocklist)_(fqdn|port)' >/dev/null 2>&1
}

full_installed() {
	if command -v apk >/dev/null 2>&1; then
		apk info -e dnsmasq-full >/dev/null 2>&1
		return $?
	fi
	if command -v opkg >/dev/null 2>&1; then
		opkg status dnsmasq-full 2>/dev/null |
			grep -F 'Status: install ok installed' >/dev/null 2>&1
		return $?
	fi
	return 1
}

compile_options() {
	command -v dnsmasq >/dev/null 2>&1 || return 1
	dnsmasq --version 2>/dev/null |
		sed -n 's/^Compile time options: //p' | sed -n '1p'
}

check_capability() {
	required=0
	if feature_requested; then
		required=1
	fi

	if ! full_installed; then
		if [ "$required" -eq 1 ]; then
			echo 'dnsmasq_error=dnsmasq-full-required-for-autonomous-lists' >&2
			return 1
		fi
		printf 'dnsmasq_full=optional-not-installed\n'
		return 0
	fi

	options=$(compile_options || true)
	case " $options " in
		*' nftset '*) set_support=nftset ;;
		*' ipset '*) set_support=ipset ;;
		*) set_support=missing ;;
	esac
	printf 'dnsmasq_full=installed\n'
	printf 'dnsmasq_set_support=%s\n' "$set_support"
	if [ "$required" -eq 1 ] && [ "$set_support" = missing ]; then
		echo 'dnsmasq_error=dnsmasq-full-has-no-nftset-or-ipset-support' >&2
		return 1
	fi
	[ "$required" -eq 0 ] || printf 'dnsmasq_feature_gate=pass\n'
}

install_capability() {
	[ "$(id -u 2>/dev/null || printf 1)" = 0 ] || {
		echo 'dnsmasq_error=root-required-for-install' >&2
		return 1
	}
	if full_installed; then
		check_capability
		return $?
	fi
	if command -v apk >/dev/null 2>&1; then
		apk add dnsmasq-full
	elif command -v opkg >/dev/null 2>&1; then
		opkg install dnsmasq-full
	else
		echo 'dnsmasq_error=no-supported-package-manager' >&2
		return 1
	fi
	# Do not delete dnsmasq, rewrite its UCI file, or restart the service here.
	# The administrator must verify the package transaction and run dnsmasq
	# --test before any deliberate service reload.
	check_capability
}

case "$action" in
	check) check_capability ;;
	install) install_capability ;;
	*)
		echo 'usage: dnsmasq-capability.sh {check|install}' >&2
		exit 2
		;;
esac
