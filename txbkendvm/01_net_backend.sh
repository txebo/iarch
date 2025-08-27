#!/usr/bin/env bash
set -euo pipefail

# Find first connected interface
IFACE="$(nmcli -t -f DEVICE,STATE d | awk -F: '$2=="connected"{print $1; exit}')"
if [ -z "${IFACE:-}" ]; then
  echo "No connected interface found."
  exit 1
fi

# Remove previous connection with the same name (idempotent)
nmcli -t -f NAME c | grep -q '^txbkendvm-static$' && nmcli con delete txbkendvm-static || true

# Create static profile
nmcli con add type ethernet ifname "$IFACE" con-name txbkendvm-static \
  ipv4.method manual ipv4.addresses 10.99.64.10/24 ipv4.gateway 10.99.64.1 \
  ipv4.dns "1.1.1.1,8.8.8.8" autoconnect yes || true

nmcli con up txbkendvm-static || true

echo "Testing connectivity..."
ping -c 2 10.99.64.1 || true
command -v drill >/dev/null 2>&1 && drill google.com || ping -c 2 8.8.8.8 || true
