#!/usr/bin/env sh
set -eu
# net-1-bkend.sh — red fija + SMB para BKEND 192.168.1.x
# Valores fijos pedidos por el usuario; simple y directo.

# Teclado
loadkeys la-latin1 2>/dev/null || true

# Detectar interfaz (primera ethernet)
IFACE="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth|eno|ens|enp)' | head -n1 || true)"
[ -n "${IFACE:-}" ] || { echo "[ERR] No NIC (en*/eth*)"; exit 1; }

# IP/GW/DNS
ip addr flush dev "$IFACE" || true
ip link set "$IFACE" up
ip addr add 192.168.1.21/24 dev "$IFACE"
ip route replace default via 192.168.1.1 dev "$IFACE"
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" >/etc/resolv.conf

# Pruebas rapidas (no fatales)
ping -c1 -W1 192.168.1.1 >/dev/null 2>&1 || echo "[WARN] GW no responde"
ping -c1 -W1 192.168.1.67 >/dev/null 2>&1 || echo "[WARN] Host SMB no responde"

# Utilerias basicas para el live
pacman -Syy --noconfirm || true
pacman -Sy --noconfirm archlinux-keyring || true
pacman -Sy --noconfirm git wget dos2unix archinstall cifs-utils

# Credenciales SMB
mkdir -p /etc/cifs-creds /mnt/shared
chmod 700 /etc/cifs-creds
cat >/etc/cifs-creds/Neural-TXIA_shared.cred <<'EOF'
username=smbtxvm
password=aalH#@wcVJs@lWyJ
domain=Neural-TXIA
EOF
chmod 600 /etc/cifs-creds/Neural-TXIA_shared.cred

# Montaje CIFS
mount -t cifs "//192.168.1.67/shared" /mnt/shared   -o "credentials=/etc/cifs-creds/Neural-TXIA_shared.cred,vers=3.1.1,sec=ntlmssp,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755"   || mount -t cifs "//192.168.1.67/shared" /mnt/shared   -o "credentials=/etc/cifs-creds/Neural-TXIA_shared.cred,vers=3.0,sec=ntlmssp,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755"

# Fstab automontaje on-demand
FSTAB_LINE="//192.168.1.67/shared /mnt/shared cifs credentials=/etc/cifs-creds/Neural-TXIA_shared.cred,vers=3.1.1,sec=ntlmssp,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755,x-systemd.automount,_netdev,noauto 0 0"
grep -Fq "$FSTAB_LINE" /etc/fstab || echo "$FSTAB_LINE" >> /etc/fstab
systemctl daemon-reload || true
systemctl restart remote-fs.target || true

echo "[OK] Listo. NIC=$IFACE  IP=192.168.1.21/24  GW=192.168.1.1  SMB=//192.168.1.67/shared -> /mnt/shared"
ip route | sed -n '1,3p' || true
ls -la /mnt/shared 2>/dev/null || true
