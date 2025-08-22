#!/usr/bin/env bash
set -euo pipefail

# setup-smb-client.sh
# Arch Linux: configurar cliente SMB para montar un share de Windows
# Requisitos: red funcionando entre Arch (cliente) y Windows (servidor)

# ---------- CONFIG (ajusta si hace falta) ----------
SERVER_IP="10.99.64.1"             # IP del Windows 11
SHARE_NAME="txVMsharedvolume"      # nombre del recurso compartido en Windows
MOUNT_POINT="/mnt/winshare"        # punto de montaje en Arch

SMB_USER="smbtxVM"                 # usuario local en Windows
SMB_PASS="aalH#@wcVJs@lWyJ"        # contraseña (usa credenciales reales)
SMB_DOMAIN=""                      # deja vacio para equipo local; o "WORKGROUP" si aplica

# Mapear archivos al usuario normal de Arch (si existe); si no, root
LINUX_USER="${SUDO_USER:-$(id -un)}"
LINUX_UID="$(id -u "$LINUX_USER")"
LINUX_GID="$(id -g "$LINUX_USER")"

CREDS_DIR="/etc/cifs-creds"
CREDS_FILE="$CREDS_DIR/${SERVER_IP//./-}_${SHARE_NAME}.creds"

# Opciones de CIFS (SMB3/NTLMSSP). Puedes bajar a vers=2.1 si lo necesitas.
CIFS_OPTS="credentials=$CREDS_FILE,uid=$LINUX_UID,gid=$LINUX_GID,iocharset=utf8,vers=3.0,sec=ntlmssp,_netdev,x-systemd.automount,nofail,file_mode=0664,dir_mode=0775"

# ---------- FUNCIONES ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "[!!] falta comando: $1"; exit 1; }; }
tcp_ok() { timeout 6 bash -c ">/dev/tcp/$SERVER_IP/445" >/dev/null 2>&1; }

# ---------- PRECHECKS ----------
[ "$(id -u)" -eq 0 ] || { echo "[!!] ejecuta como root"; exit 1; }

for c in pacman mount umount grep sed awk; do need "$c"; done

echo "[*] instalando paquetes cliente SMB (cifs-utils, smbclient) si faltan..."
pacman -Sy --needed --noconfirm cifs-utils smbclient >/dev/null

echo "[*] probando conectividad SMB a $SERVER_IP:445 ..."
tcp_ok || { echo "[!!] no hay acceso TCP al puerto 445 de $SERVER_IP"; exit 1; }

# ---------- CREDENCIALES ----------
echo "[*] creando credenciales seguras en $CREDS_FILE ..."
install -d -m 700 "$CREDS_DIR"
{
  echo "username=$SMB_USER"
  echo "password=$SMB_PASS"
  [ -n "$SMB_DOMAIN" ] && echo "domain=$SMB_DOMAIN"
} > "$CREDS_FILE"
chmod 600 "$CREDS_FILE"

# ---------- PRUEBA DE ENUMERACION (opcional pero util) ----------
echo "[*] enumerando shares disponibles en //$SERVER_IP ..."
smbclient -L "//$SERVER_IP" -m SMB3 -U "$SMB_USER%$SMB_PASS" || {
  echo "[!!] autenticacion SMB fallida (usuario/clave/dominio)"; exit 1;
}

# ---------- MONTAJE ----------
echo "[*] preparando punto de montaje $MOUNT_POINT ..."
mkdir -p "$MOUNT_POINT"
chown "$LINUX_UID:$LINUX_GID" "$MOUNT_POINT"

# Si ya estaba montado, desmontar
mountpoint -q "$MOUNT_POINT" && umount "$MOUNT_POINT" || true

# Agregar/actualizar entrada en /etc/fstab
echo "[*] registrando en /etc/fstab ..."
FSTAB_LINE="//${SERVER_IP}/${SHARE_NAME}  ${MOUNT_POINT}  cifs  ${CIFS_OPTS}  0  0"
# elimina entradas anteriores de ese share/punto, si existen
sed -i "\|^//${SERVER_IP}/${SHARE_NAME}[[:space:]]\+${MOUNT_POINT}[[:space:]]\+cifs|d" /etc/fstab
echo "$FSTAB_LINE" >> /etc/fstab

echo "[*] montando ahora (mount -a) ..."
mount -a

# ---------- VALIDACION R/W ----------
echo "[*] validando acceso en ${MOUNT_POINT} ..."
ls -la "$MOUNT_POINT" | head -n 50 || true

TEST_FILE="$MOUNT_POINT/.smb_client_rw_test_$$"
set +e
echo "rw-test $(date -Iseconds)" > "$TEST_FILE"
RW=$?
set -e
if [ $RW -eq 0 ]; then
  echo "[OK] escritura permitida; limpiando archivo de prueba..."
  rm -f "$TEST_FILE"
else
  echo "[!!] no se pudo escribir en el share (probablemente permisos solo lectura en SMB o NTFS)."
fi

echo
echo "[OK] share montado: ${MOUNT_POINT}"
echo "[OK] entrada en /etc/fstab:"
echo "     $FSTAB_LINE"
echo
echo "Para desmontar:    umount ${MOUNT_POINT}"
echo "Para montar luego: mount ${MOUNT_POINT}   (o automaticamente por systemd-automount)"
