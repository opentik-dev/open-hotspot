#!/bin/sh
# family-captive-preflight.sh — fail-closed readiness gate for Family Captive.
#
# The existing Open-HotSpot integration manages one openNDS gateway. A family
# captive plane must have a separately verified openNDS instance before an
# SSID/VLAN is exposed. This helper is deliberately read-only: it does not
# create a bridge, alter UCI, start a daemon, or change firewall policy.

UCI_BIN="${OPEN_HOTSPOT_UCI_BIN:-uci}"

uci_get() {
	"$UCI_BIN" -q get "$1" 2>/dev/null || true
}

opennds_sections() {
	"$UCI_BIN" -q show opennds 2>/dev/null |
		sed -n 's/^opennds\.\([^.=]*\)=opennds$/\1/p'
}

primary_gateway() {
	device=$(uci_get opennds.setup.gatewayinterface)
	[ -n "$device" ] || device=$(uci_get opennds.@opennds[0].gatewayinterface)
	printf '%s\n' "$device"
}

valid_name() {
	printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_.-]+$'
}

preflight() {
	state=$(uci_get open-hotspot.family_captive.state)
	[ -n "$state" ] || state='disabled'
	family_device=$(uci_get open-hotspot.family_captive.device)
	family_network=$(uci_get open-hotspot.family_captive.network)
	enforcement=$(uci_get open-hotspot.family_captive.enforcement_adapter)
	primary=$(primary_gateway)
	sections=$(opennds_sections)
	section_count=$(printf '%s\n' "$sections" | sed '/^$/d' | wc -l | tr -d ' ')

	printf 'family_captive_state=%s\n' "$state"
	printf 'family_captive_primary_gateway=%s\n' "${primary:-unset}"
	printf 'family_captive_opennds_sections=%s\n' "$section_count"
	printf 'family_captive_device=%s\n' "${family_device:-unset}"
	printf 'family_captive_network=%s\n' "${family_network:-unset}"
	printf 'family_captive_enforcement_adapter=%s\n' "${enforcement:-unset}"

	case "$state" in
		disabled)
			printf 'family_captive_readiness=disabled\n'
			return 0
			;;
		staged|enabled) ;;
		*)
			echo 'family_captive_error=invalid-state' >&2
			return 1
			;;
	esac

	[ -n "$family_device" ] && valid_name "$family_device" || {
		echo 'family_captive_error=device-required' >&2
		return 1
	}
	[ -n "$family_network" ] && valid_name "$family_network" || {
		echo 'family_captive_error=network-required' >&2
		return 1
	}
	[ "$family_device" != "$primary" ] || {
		echo 'family_captive_error=device-must-not-share-primary-captive-bridge' >&2
		return 1
	}
	[ "$enforcement" = 'multi-instance-v1' ] || {
		echo 'family_captive_error=verified-multi-instance-adapter-required' >&2
		return 1
	}
	# Counting UCI sections is only a structural signal. It does not prove that
	# a second daemon, control socket, FAS identity, and BinAuth/session scope
	# have been verified. Keep activation blocked until that adapter exists.
	if [ "$section_count" -lt 2 ]; then
		echo 'family_captive_error=separate-opennds-instance-not-configured' >&2
		echo 'family_captive_action=do-not-create-or-enable-family-ssid-yet' >&2
		return 1
	fi

	echo 'family_captive_error=multi-instance-runtime-contract-not-yet-implemented' >&2
	echo 'family_captive_action=complete-adapter-and-field-validation-before-enabling' >&2
	return 1
}

case "${1:-}" in
	check) preflight ;;
	*) echo 'usage: family-captive-preflight.sh check' >&2; exit 2 ;;
esac
