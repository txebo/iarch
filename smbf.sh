#!/usr/bin/env bash
set -euo pipefail

# ==== Config por defecto (ajusta si lo necesitas) ====
SERVER_IP="${SERVER_IP:-192.168.1.67}"          # IP de tu PC Windows (Neural-TXIA)
SERVER_NAME="${SERVER_NAME:-Neural-TXIA}"       # Nombre del host Windows
SHARE_NAME="${SHARE_NAME:-shared}"              # Nombre del recurso compartido (\\Neural-TXIA\shared)
MOUNT_POINT="${MOUNT_POINT:-/mnt/shared}"       # Punto de montaje en Arch

# Credenciales: se leen de variables de entorno SMB_USER y SMB_PASS
# Si no vienen, se pediran (solo la password) de forma interactiva.
DOMAIN="${DOMAIN:-Neural-TXIA}"                 # Para cuenta local de Windows, usa el nombre del host
SMB_USER="${SMB_USER:-smbtxvm}"                        # p.ej. smbtxvm
SMB_PASS="${SMB_PASS:-aalH#@wcVJs@lWyJ}"                        # p.ej. aalH#@wcVJs@lWyJ

# Detectar UID/GID del usuario real para ownership de archivos montados
REAL_USER="${SUDO_USER:-$USER}"
UID_NUM="$(id -u "$REAL_USER")"
GID_NUM="$(id -g "$REAL_USER")"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta como root (usa: sudo $0)"; exit 1
fi

# Cliente CIFS
pacman -Sy --needed --noconfirm cifs-utils

# Punto de montaje
mkdir -p "$MOUNT_POINT"

# Archivo de credenciales seguro
CREDS_DIR="/etc/cifs-creds"
CREDS_FILE="$CREDS_DIR/${SERVER_NAME}_${SHARE_NAME}.cred"
mkdir -p "$CREDS_DIR"
chmod 700 "$CREDS_DIR"

# Si falta usuario, pedirlo; si falta password, pedirla sin eco
if [[ -z "$SMB_USER" ]]; then
  read -rp "Usuario SMB en Windows (${DOMAIN}\\...): " SMB_USER
fi
if [[ -z "$SMB_PASS" ]]; then
  read -rsp "Contrasena SMB para ${DOMAIN}\\${SMB_USER}: " SMB_PASS; echo
fi

cat > "$CREDS_FILE" <<EOF
username=${SMB_USER}
password=${SMB_PASS}
domain=${DOMAIN}
EOF
chmod 600 "$CREDS_FILE"

# Montaje inmediato. Si diera problema de version, cambia vers=3.1.1 por vers=3.0
echo "Montando //${SERVER_IP}/${SHARE_NAME} en ${MOUNT_POINT} ..."
mount -t cifs "//${SERVER_IP}/${SHARE_NAME}" "$MOUNT_POINT" \
  -o "credentials=${CREDS_FILE},vers=3.1.1,sec=ntlmssp,uid=${UID_NUM},gid=${GID_NUM},iocharset=utf8,file_mode=0644,dir_mode=0755"

echo "OK. Contenido inicial:"
ls -la "$MOUNT_POINT" || true

# Automontaje por demanda con systemd (noauto + x-systemd.automount)
FSTAB_LINE="//${SERVER_IP}/${SHARE_NAME} ${MOUNT_POINT} cifs credentials=${CREDS_FILE},vers=3.1.1,sec=ntlmssp,uid=${UID_NUM},gid=${GID_NUM},iocharset=utf8,file_mode=0644,dir_mode=0755,x-systemd.automount,_netdev,noauto 0 0"
if ! grep -Fq "$FSTAB_LINE" /etc/fstab; then
  echo "$FSTAB_LINE" >> /etc/fstab
fi

systemctl daemon-reload
systemctl restart remote-fs.target || true

echo
echo "Listo:"
echo " - Punto de montaje: $MOUNT_POINT"
echo " - Automontaje habilitado (acceso on-demand)."
echo " - Desmontar ahora: umount $MOUNT_POINT"
echo " - Montar manualmente: mount $MOUNT_POINT"
