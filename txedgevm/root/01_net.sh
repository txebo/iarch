#!/usr/bin/env bash
set -euo pipefail

IFACE="$(nmcli -t -f DEVICE,STATE d | awk -F: '$2=="connected"{print $1; exit}')"
if [ -z "${IFACE:-}" ]; then
  echo "No connected interface found."
  exit 1
fi

nmcli con add type ethernet ifname "$IFACE" con-name txedgevm-static \
  ipv4.method manual ipv4.addresses 10.99.64.2/24 ipv4.gateway 10.99.64.1 \
  ipv4.dns "1.1.1.1,8.8.8.8" autoconnect yes || true

nmcli con up txedgevm-static || true

echo "Testing connectivity..."
ping -c 2 10.99.64.1 || true
drill google.com @1.1.1.1 || true
