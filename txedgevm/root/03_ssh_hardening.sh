#!/usr/bin/env bash
set -euo pipefail

SSHD="/etc/ssh/sshd_config"
cp -a "$SSHD" "${SSHD}.bak.$(date +%s)"

sed -i 's/^#\?Port .*/Port 22/' "$SSHD"
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD"
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$SSHD"
echo "MaxAuthTries 3" >> "$SSHD"
echo "LoginGraceTime 30" >> "$SSHD"
echo "AllowTcpForwarding no" >> "$SSHD"
echo "X11Forwarding no" >> "$SSHD"

systemctl restart sshd
systemctl status fail2ban --no-pager || true
