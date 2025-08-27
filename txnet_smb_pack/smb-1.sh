#!/usr/bin/env sh
set -eu
# smb-1.sh — solo monta el share con credenciales fijas.
mkdir -p /etc/cifs-creds /mnt/shared
chmod 700 /etc/cifs-creds
cat >/etc/cifs-creds/Neural-TXIA_shared.cred <<'EOF'
username=smbtxvm
password=aalH#@wcVJs@lWyJ
domain=Neural-TXIA
EOF
chmod 600 /etc/cifs-creds/Neural-TXIA_shared.cred

mount -t cifs "//192.168.1.67/shared" /mnt/shared   -o "credentials=/etc/cifs-creds/Neural-TXIA_shared.cred,vers=3.1.1,sec=ntlmssp,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755"   || mount -t cifs "//192.168.1.67/shared" /mnt/shared   -o "credentials=/etc/cifs-creds/Neural-TXIA_shared.cred,vers=3.0,sec=ntlmssp,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0644,dir_mode=0755"

echo "[OK] Montado //192.168.1.67/shared -> /mnt/shared"
