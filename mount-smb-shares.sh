#!/usr/bin/env bash
set -euo pipefail

# mount-smb-shares.sh
# Crea credenciales para CIFS con usuario 'smbtxVM', monta dos shares:
#   //WINDOWS_HOST/DevShare          -> /mnt/devshare
#   //WINDOWS_HOST/txVMsharedvolume  -> /mnt/sharedvolume
# y los deja persistentes en /etc/fstab.
#
# Variables:
#   WINDOWS_HOST  (recomendado: nombre NetBIOS del host Windows; si usas IP, igual funciona)
#   OWNER_USER    (por defecto 'tx' si existe, si no 'root')
#   SMB_PASS      (si no esta seteada, la pedira)
#
# Uso:
#   WINDOWS_HOST=PC-DE-EUSEBIO SMB_PASS='tu_password' bash mount-smb-shares.sh
#   # o interactivo: bash mount-smb-shares.sh  (te pedira host y password)

USERNAME="smbtxVM"
WINDOWS_HOST="${WINDOWS_HOST:-}"
OWNER_USER="${OWNER_USER:-}"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Run as root."
    exit 1
  fi
}

detect_owner() {
  if [[ -n "$OWNER_USER" ]]; then
    echo "$OWNER_USER"
    return
  fi
  if id -u tx >/dev/null 2>&1; then
    echo "tx"
  else
    echo "root"
  fi
}

prompt_host() {
  if [[ -z "$WINDOWS_HOST" ]]; then
    echo -n "Enter Windows host name or IP (e.g., DESKTOP123 or 10.99.64.1): "
    read -r WINDOWS_HOST
  fi
}

get_password() {
  if [[ -n "${SMB_PASS:-}" ]]; then
    echo "$SMB_PASS"
    return
  fi
  read -rsp "Enter password for user ${USERNAME}: " p
  echo
  echo "$p"
}

require_root
prompt_host
OWNER_USER="$(detect_owner)"
OWNER_UID="$(id -u "$OWNER_USER")"
OWNER_GID="$(id -g "$OWNER_USER")"

echo "[*] Creating mount points..."
install -d -m 0755 /mnt/devshare
install -d -m 0755 /mnt/sharedvolume

echo "[*] Writing CIFS credentials to /root/.smbcredentials (0600)..."
install -m 0600 /root/.smbcredentials /dev/null
PASS="$(get_password)"
cat >/root/.smbcredentials <<EOF
username=${USERNAME}
password=${PASS}
EOF
chmod 600 /root/.smbcredentials

echo "[*] Mounting now..."
mount -t cifs //${WINDOWS_HOST}/DevShare /mnt/devshare \
  -o credentials=/root/.smbcredentials,iocharset=utf8,vers=3.1.1,uid=${OWNER_UID},gid=${OWNER_GID},file_mode=0664,dir_mode=0775

mount -t cifs //${WINDOWS_HOST}/txVMsharedvolume /mnt/sharedvolume \
  -o credentials=/root/.smbcredentials,iocharset=utf8,vers=3.1.1,uid=${OWNER_UID},gid=${OWNER_GID},file_mode=0664,dir_mode=0775

echo "[*] Persisting to /etc/fstab..."
grep -qE "^//${WINDOWS_HOST}/DevShare\s" /etc/fstab || \
  echo "//${WINDOWS_HOST}/DevShare /mnt/devshare cifs credentials=/root/.smbcredentials,iocharset=utf8,vers=3.1.1,uid=${OWNER_UID},gid=${OWNER_GID},file_mode=0664,dir_mode=0775 0 0" >> /etc/fstab

grep -qE "^//${WINDOWS_HOST}/txVMsharedvolume\s" /etc/fstab || \
  echo "//${WINDOWS_HOST}/txVMsharedvolume /mnt/sharedvolume cifs credentials=/root/.smbcredentials,iocharset=utf8,vers=3.1.1,uid=${OWNER_UID},gid=${OWNER_GID},file_mode=0664,dir_mode=0775 0 0" >> /etc/fstab

echo
echo "Done."
echo "- Mounted: /mnt/devshare and /mnt/sharedvolume"
echo "- Owner mapped to: ${OWNER_USER} (uid=${OWNER_UID}, gid=${OWNER_GID})"
echo "- Reboot-resilient via /etc/fstab."
