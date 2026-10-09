#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/starter-kit/root/usr/lib/open-hotspot/network-audit.sh"
tmp=$(mktemp -d /tmp/open-hotspot-network-audit.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

sh -n "$script"
test -x "$script"

cat > "$tmp/ip" <<'EOF'
#!/bin/sh
case "$*" in
  "-4 route show default") echo 'default via 203.0.113.1 dev wan0' ;;
  "link show dev tailscale0") exit 0 ;;
  "-4 route get 198.51.100.20") echo '198.51.100.20 via 203.0.113.1 dev wan0 src 203.0.113.2' ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/uci" <<'EOF'
#!/bin/sh
case "$*" in
  *open-hotspot.global.client_network*) echo iot ;;
  *firewall.open_hotspot_clients_to_wan.src*) echo open_hotspot_clients ;;
  *firewall.open_hotspot_clients_to_wan.dest*) echo wan ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/ndsctl" <<'EOF'
#!/bin/sh
echo 'Current clients: 2'
EOF
cat > "$tmp/tailscale" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/ip" "$tmp/uci" "$tmp/ndsctl" "$tmp/tailscale"

PATH="$tmp:$PATH" OPEN_HOTSPOT_IP_BIN="$tmp/ip" OPEN_HOTSPOT_UCI_BIN="$tmp/uci" \
OPEN_HOTSPOT_NDSCTL_BIN="$tmp/ndsctl" "$script" summary > "$tmp/summary"
grep -Fx 'default_interface=wan0' "$tmp/summary" >/dev/null
grep -Fx 'tailscale_interface=present' "$tmp/summary" >/dev/null
grep -Fx 'opennds_clients=2' "$tmp/summary" >/dev/null
grep -Fx 'iot_wan_forward_dest=wan' "$tmp/summary" >/dev/null

OPEN_HOTSPOT_IP_BIN="$tmp/ip" "$script" route 198.51.100.20 > "$tmp/route"
grep -Fx 'route_lookup=reachable' "$tmp/route" >/dev/null
grep -Fx 'route_device=wan0' "$tmp/route" >/dev/null
! OPEN_HOTSPOT_IP_BIN="$tmp/ip" "$script" route invalid >/dev/null 2>&1

printf '%s\n' 'network-audit-contract-ok'
