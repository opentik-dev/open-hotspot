#!/bin/sh
# Validate the declarative two-plane lab contract. This is not an openNDS launcher.
set -eu

usage() { echo 'usage: family-captive-lab-validate.sh <plan-file>' >&2; }
die() { echo "family-captive-lab: $1" >&2; exit 1; }

[ "$#" -eq 1 ] || { usage; exit 2; }
plan_file=$1
[ -r "$plan_file" ] || die 'plan-file-unreadable'

value() { sed -n "s/^$1=//p" "$plan_file" | sed -n '1p'; }
safe_token() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_.-]+$'; }
safe_runtime_dir() { printf '%s' "$1" | grep -Eq '^/tmp/opennds-[A-Za-z0-9_.-]+$'; }
safe_socket() { printf '%s' "$1" | grep -Eq '^opennds-[A-Za-z0-9_.-]+/ndsctl\.sock$'; }
safe_runtime_file() { printf '%s' "$1" | grep -Eq '^/tmp/opennds-[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.(pid|log)$'; }
safe_wrapper() { printf '%s' "$1" | grep -Eq '^/usr/lib/open-hotspot/adapters/[A-Za-z0-9_.-]+\.sh$'; }
safe_ipv4() { printf '%s' "$1" | awk -F. 'NF == 4 { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i > 255) exit 1; exit 0 } { exit 1 }'; }
safe_port() { printf '%s' "$1" | grep -Eq '^[1-9][0-9]{0,4}$' && [ "$1" -le 65535 ]; }
safe_chain() { printf '%s' "$1" | grep -Eq '^opennds_[A-Za-z0-9_]+$'; }
require_value() { [ -n "$2" ] || die "$1-required"; }

guest_device=$(value guest.device)
family_device=$(value family.device)
guest_runtime=$(value guest.runtime_dir)
family_runtime=$(value family.runtime_dir)
guest_socket=$(value guest.ndsctlsocket)
family_socket=$(value family.ndsctlsocket)
guest_wrapper=$(value guest.ndsctl_wrapper)
family_wrapper=$(value family.ndsctl_wrapper)
guest_pid=$(value guest.pid_file)
family_pid=$(value family.pid_file)
guest_log=$(value guest.log_file)
family_log=$(value family.log_file)
guest_gateway=$(value guest.gateway_name)
family_gateway=$(value family.gateway_name)
guest_address=$(value guest.gateway_address)
family_address=$(value family.gateway_address)
guest_plane=$(value guest.fas_plane)
family_plane=$(value family.fas_plane)
guest_fas_port=$(value guest.fas_listener_port)
family_fas_port=$(value family.fas_listener_port)
guest_chain=$(value guest.nft_chain)
family_chain=$(value family.nft_chain)
guest_service=$(value guest.procd_service)
family_service=$(value family.procd_service)

for item in \
	"guest-device:$guest_device" "family-device:$family_device" \
	"guest-runtime:$guest_runtime" "family-runtime:$family_runtime" \
	"guest-socket:$guest_socket" "family-socket:$family_socket" \
	"guest-wrapper:$guest_wrapper" "family-wrapper:$family_wrapper" \
	"guest-pid:$guest_pid" "family-pid:$family_pid" \
	"guest-log:$guest_log" "family-log:$family_log" \
	"guest-gateway:$guest_gateway" "family-gateway:$family_gateway" \
	"guest-address:$guest_address" "family-address:$family_address" \
	"guest-plane:$guest_plane" "family-plane:$family_plane" \
	"guest-fas-port:$guest_fas_port" "family-fas-port:$family_fas_port" \
	"guest-chain:$guest_chain" "family-chain:$family_chain" \
	"guest-service:$guest_service" "family-service:$family_service"; do
	label=${item%%:*}
	content=${item#*:}
	require_value "$label" "$content"
done

safe_token "$guest_device" || die 'guest-device-invalid'
safe_token "$family_device" || die 'family-device-invalid'
safe_runtime_dir "$guest_runtime" || die 'guest-runtime-invalid'
safe_runtime_dir "$family_runtime" || die 'family-runtime-invalid'
safe_socket "$guest_socket" || die 'guest-socket-invalid'
safe_socket "$family_socket" || die 'family-socket-invalid'
safe_wrapper "$guest_wrapper" || die 'guest-wrapper-invalid'
safe_wrapper "$family_wrapper" || die 'family-wrapper-invalid'
safe_runtime_file "$guest_pid" || die 'guest-pid-invalid'
safe_runtime_file "$family_pid" || die 'family-pid-invalid'
safe_runtime_file "$guest_log" || die 'guest-log-invalid'
safe_runtime_file "$family_log" || die 'family-log-invalid'
safe_token "$guest_gateway" || die 'guest-gateway-invalid'
safe_token "$family_gateway" || die 'family-gateway-invalid'
safe_ipv4 "$guest_address" || die 'guest-address-invalid'
safe_ipv4 "$family_address" || die 'family-address-invalid'
safe_token "$guest_plane" || die 'guest-plane-invalid'
safe_token "$family_plane" || die 'family-plane-invalid'
safe_port "$guest_fas_port" || die 'guest-fas-port-invalid'
safe_port "$family_fas_port" || die 'family-fas-port-invalid'
safe_chain "$guest_chain" || die 'guest-chain-invalid'
safe_chain "$family_chain" || die 'family-chain-invalid'
safe_token "$guest_service" || die 'guest-service-invalid'
safe_token "$family_service" || die 'family-service-invalid'

[ "$guest_device" != "$family_device" ] || die 'device-collision'
[ "$guest_runtime" != "$family_runtime" ] || die 'runtime-collision'
[ "$guest_socket" != "$family_socket" ] || die 'control-socket-collision'
[ "$guest_wrapper" != "$family_wrapper" ] || die 'ndsctl-wrapper-collision'
[ "$guest_pid" != "$family_pid" ] || die 'pid-file-collision'
[ "$guest_log" != "$family_log" ] || die 'log-file-collision'
[ "$guest_gateway" != "$family_gateway" ] || die 'gateway-name-collision'
[ "$guest_address" != "$family_address" ] || die 'gateway-address-collision'
[ "$guest_plane" != "$family_plane" ] || die 'fas-plane-collision'
[ "$guest_fas_port" != "$family_fas_port" ] || die 'fas-listener-port-collision'
[ "$guest_chain" != "$family_chain" ] || die 'nft-chain-collision'
[ "$guest_service" != "$family_service" ] || die 'procd-service-collision'

printf 'family_captive_lab_contract=ok\n'
printf 'guest_device=%s\nfamily_device=%s\n' "$guest_device" "$family_device"
printf 'guest_fas_listener_port=%s\nfamily_fas_listener_port=%s\n' "$guest_fas_port" "$family_fas_port"
