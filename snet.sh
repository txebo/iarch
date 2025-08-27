#!/usr/bin/env sh
set -euo pipefail

# =====================[ CONFIGURACION GLOBAL ]=====================
KEYMAP="${KEYMAP:-la-latin1}"
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"

# CIFS/SMB comunes
SERVER_NAME="${SERVER_NAME:-Neural-TXIA}"
SHARE_NAME="${SHARE_NAME:-shared}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/shared}"
DOMAIN="${DOMAIN:-Neural-TXIA}"
SMB_USER="${SMB_USER:-smbtxvm}"
SMB_PASS="${SMB_PASS:-}"   # si queda vacio se pedira
PROFILE="${PROFILE:-}"     # A o B para forzar perfil

# =====================[ PERFILES DE RED ]=========================
# Perfil A: LAN 192.168.68.0/24
A_IP_CIDR="${A_IP_CIDR:-192.168.68.20/24}"
A_GW="${A_GW:-192.168.68.1}"
A_SERVER_IP="${A_SERVER_IP:-192.168.68.128}"

# Perfil B: LAN 192.168.1.0/24
B_IP_CIDR="${B_IP_CIDR:-192.168.1.20/24}"
B_GW="${B_GW:-192.168.1.1}"
B_SERVER_IP="${B_SERVER_IP:-192.168.1.67}"

# =======================[ FUNCIONES ]=============================
msg() { printf "%s\n" "$*"; }

detect_iface() {
  ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth|eno|ens|enp)' | head -n1
}

apply_dns() {
  printf "nameserver %s\nnameserver %s\n" "$DNS1" "$DNS2" > /etc/resolv.conf
}

flush_iface() {
  dev="$1"
  ip addr flush dev "$dev" || true
  ip route flush dev "$dev" || true
  ip link set "$dev" up
}

apply_profile() {
  dev="$1"; ip_cidr="$2"; gw="$3"
  msg ">>> Perfil: IP=${ip_cidr} GW=${gw} en ${dev}"
  flush_iface "$dev"
  ip addr add "$ip_cidr" dev "$dev"
  ip route replace default via "$gw" dev "$dev"
  apply_dns
}

test_connectivity() {
  server_ip="$1"
  ok=0
  ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && ok=$((ok+1))
  ping -c1 -W2 archlinux.org >/dev/null 2>&1 && ok=$((ok+1))
  ping -c1 -W2 "$server_ip" >/dev/null 2>&1 && ok=$((ok+1))
  [ "$ok" -ge 2 ]  # exito si pasan >=2 pruebas
}

mount_smb() {
  server_ip="$1"
  real_user="${SUDO_USER:-$USER}"
  uid_num="$(id -u "$real_user")"
  gid_num="$(id -g "$real_user")"

  [ "$(id -u)" -eq 0 ] || { msg "Ejecuta como root (sudo)"; exit 1; }

  pacman -Sy --needed --noconfirm cifs-utils

  mkdir -p "$MOUNT_POINT"

  creds_dir="/etc/cifs-creds"
  creds_file="$creds_dir/${SERVER_NAME}_${SHARE_NAME}.cred"
  mkdir -p "$creds_dir"
  chmod 700 "$creds_dir"

  if [ -z "${SMB_USER:-}" ]; then
    read -r -p "Usuario SMB (${DOMAIN}\\...): " SMB_USER
  fi
  if [ -z "${SMB_PASS:-}" ]; then
    read -r -s -p "Contrasena SMB para ${DOMAIN}\\${SMB_USER}: " SMB_PASS; echo
  fi

  cat > "$creds_file" <<EOF
username=${SMB_USER}
password=${SMB_PASS}
domain=${DOMAIN}
EOF
  chmod 600 "$creds_file"

  msg "Montando //${server_ip}/${SHARE_NAME} en ${MOUNT_POINT} ..."
  if ! mount -t cifs "//${server_ip}/${SHARE_NAME}" "$MOUNT_POINT" \
      -o "credentials=${creds_file},vers=3.1.1,sec=ntlmssp,uid=${uid_num},gid=${gid_num},iocharset=utf8,file_mode=0644,dir_mode=0755"; then
    # Fallback a SMB 3.0 si 3.1.1 falla
    mount -t cifs "//${server_ip}/${SHARE_NAME}" "$MOUNT_POINT" \
      -o "credentials=${creds_file},vers=3.0,sec=ntlmssp,uid=${uid_num},gid=${gid_num},iocharset=utf8,file_mode=0644,dir_mode=0755"
  fi

  # Fstab con automontaje on-demand
  fstab_line="//${server_ip}/${SHARE_NAME} ${MOUNT_POINT} cifs credentials=${creds_file},vers=3.1.1,sec=ntlmssp,uid=${uid_num},gid=${gid_num},iocharset=utf8,file_mode=0644,dir_mode=0755,x-systemd.automount,_netdev,noauto 0 0"
  grep -Fq "$fstab_line" /etc/fstab || echo "$fstab_line" >> /etc/fstab
  systemctl daemon-reload
  systemctl restart remote-fs.target || true

  ls -la "$MOUNT_POINT" || true
}

# =====================[ INICIO ]========================
msg "=== Configuracion de teclado ==="
loadkeys "$KEYMAP" || true

msg "=== Detectando interfaz de red ==="
IFACE="$(detect_iface || true)"
[ -n "${IFACE:-}" ] || { msg "No se encontro interfaz valida (en*/eth*)."; exit 1; }
msg "Usando interfaz: $IFACE"

# =====================[ SELECCION Y PRUEBA DE PERFIL ]============
chosen_server=""
if [ "$PROFILE" = "A" ] || [ -z "$PROFILE" ]; then
  apply_profile "$IFACE" "$A_IP_CIDR" "$A_GW"
  if test_connectivity "$A_SERVER_IP"; then
    msg "Perfil A (192.168.68.0/24) OK."
    chosen_server="$A_SERVER_IP"
  else
    msg "Perfil A sin conectividad suficiente."
  fi
fi

if [ -z "$chosen_server" ] && { [ "$PROFILE" = "B" ] || [ -z "$PROFILE" ]; }; then
  apply_profile "$IFACE" "$B_IP_CIDR" "$B_GW"
  if test_connectivity "$B_SERVER_IP"; then
    msg "Perfil B (192.168.1.0/24) OK."
    chosen_server="$B_SERVER_IP"
  else
    msg "Perfil B sin conectividad suficiente."
  fi
fi

[ -n "$chosen_server" ] || { msg "No se logro conectividad con ningun perfil."; ip route || true; ip -br addr || true; exit 1; }

# =====================[ UTILERIAS DEL LIVE ]======================
msg "=== Sincronizando indices y utilerias del live ==="
pacman -Syy --noconfirm
pacman -Sy --noconfirm archlinux-keyring || true
pacman -Sy --noconfirm git wget dos2unix archinstall

# =====================[ MONTAR SMB ]==============================
mount_smb "$chosen_server"

# Validar carpeta esperada
if [ ! -d "${MOUNT_POINT}/archinstall" ]; then
  msg "ADVERTENCIA: ${MOUNT_POINT}/archinstall no existe en el share."
else
  msg "OK: Existe ${MOUNT_POINT}/archinstall"
fi

msg ""
msg "Listo:"
msg " - Recurso: //${chosen_server}/${SHARE_NAME} -> ${MOUNT_POINT}"
msg " - Perfil seleccionado correctamente."
msg " - Automontaje on-demand habilitado."
