#!/usr/bin/env sh
# snet.sh – teclado, red (2 perfiles), utilerias y SMB
# Seguro para ISO (sin dos2unix, sin pipefail)
# --------------------------------------------------

# 0) Autolimpieza CRLF/BOM y re-ejecucion
if grep -q "$'\r'" "$0" 2>/dev/null; then :; fi
if grep -q "$(printf '\r')" "$0" 2>/dev/null; then
  tmp="$(mktemp)"; tr -d '\r' <"$0" >"$tmp"; chmod +x "$tmp"; exec "$tmp" "$@"
fi
case "$(head -c3 "$0" | od -An -t x1 | tr -d ' ')" in
  efbbbf) tmp="$(mktemp)"; tail -c +4 "$0" >"$tmp"; chmod +x "$tmp"; exec "$tmp" "$@";;
esac

set -eu

# =============== CONFIG POR DEFECTO (puedes exportar) ===============
KEYMAP="${KEYMAP:-la-latin1}"

# Perfil A (192.168.68.0/24)
A_IP_CIDR="${A_IP_CIDR:-192.168.68.20/24}"
A_GW="${A_GW:-192.168.68.1}"
A_SERVER_IP="${A_SERVER_IP:-192.168.68.128}"

# Perfil B (192.168.1.0/24)
B_IP_CIDR="${B_IP_CIDR:-192.168.1.20/24}"
B_GW="${B_GW:-192.168.1.1}"
B_SERVER_IP="${B_SERVER_IP:-192.168.1.67}"

# SMB
SERVER_NAME="${SERVER_NAME:-Neural-TXIA}"
SHARE_NAME="${SHARE_NAME:-shared}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/shared}"
DOMAIN="${DOMAIN:-Neural-TXIA}"
SMB_USER="${SMB_USER:-smbtxvm}"
SMB_PASS="${SMB_PASS:-}"   # si queda vacio se pedira
PROFILE="${PROFILE:-}"     # A o B para forzar

DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"

# ========================== HELPERS ==========================
msg() { printf "%s\n" "$*"; }
strip_cr() { printf "%s" "$1" | tr -d '\r'; }
is_ipv4() { printf "%s" "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; }

detect_iface() {
  # Preferir interfaz UP; si no, tomar la primera ethernet
  ip -o link show up    2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(en|eth|eno|ens|enp)' | head -n1 ||
  ip -o link show       2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(en|eth|eno|ens|enp)' | head -n1 || true
}

apply_dns() {
  printf "nameserver %s\nnameserver %s\n" "$DNS1" "$DNS2" > /etc/resolv.conf || true
}

flush_iface() {
  dev="$1"
  ip addr flush dev "$dev" 2>/dev/null || true
  ip route flush dev "$dev" 2>/dev/null || true
  ip neigh flush dev "$dev" 2>/dev/null || true
  ip link set "$dev" up
}

wait_gw() {
  gw="$1"; tries=0
  while :; do
    ping -c1 -W1 "$gw" >/dev/null 2>&1 && return 0
    tries=$((tries+1)); [ "$tries" -ge 10 ] && return 1
    sleep 1
  done
}

apply_profile() {
  dev="$1"
  ip_cidr="$(strip_cr "$2")"
  gw="$(strip_cr "$3")"

  [ -n "$gw" ] && is_ipv4 "$gw" || { msg "[ERR] Gateway invalido: '$gw'"; return 1; }

  msg ">>> Perfil: IP=$ip_cidr  GW=$gw  IFACE=$dev"
  flush_iface "$dev"
  ip addr replace "$ip_cidr" dev "$dev"
  apply_dns

  ip route del default >/dev/null 2>&1 || true
  ip route add default via "$gw" dev "$dev"

  if ! wait_gw "$gw"; then
    msg "[ERR] El gateway $gw no responde"; return 1
  fi

  if ! ip route get 1.1.1.1 2>/dev/null | grep -q "via $gw .* dev $dev"; then
    msg "[ERR] La ruta por defecto NO quedo via $gw en $dev"
    ip route || true
    return 1
  fi

  ip -br addr show "$dev" || true
  ip route | sed -n '1,5p' || true
  return 0
}

test_connectivity() {
  server_ip="$(strip_cr "$1")"
  ok=0
  ping -c1 -W2 1.1.1.1      >/dev/null 2>&1 && ok=$((ok+1))
  ping -c1 -W2 archlinux.org >/dev/null 2>&1 && ok=$((ok+1))
  ping -c1 -W2 "$server_ip"  >/dev/null 2>&1 && ok=$((ok+1))
  [ "$ok" -ge 2 ]
}

mount_smb() {
  server_ip="$(strip_cr "$1")"
  real_user="${SUDO_USER:-$USER}"
  uid_num="$(id -u "$real_user")"
  gid_num="$(id -g "$real_user")"

  if ! command -v mount.cifs >/dev/null 2>&1; then
    # intentar instalar rapidamente si hay red
    if command -v pacman >/dev/null 2>&1; then
      pacman -Sy --noconfirm cifs-utils || true
    fi
  fi

  [ -x /usr/bin/mount.cifs ] || { msg "[WARN] cifs-utils no disponible; omito montaje"; return 0; }

  mkdir -p "$MOUNT_POINT"

  creds_dir="/etc/cifs-creds"
  creds_file="$creds_dir/${SERVER_NAME}_${SHARE_NAME}.cred"
  mkdir -p "$creds_dir"; chmod 700 "$creds_dir"

  [ -n "$SMB_USER" ] || read -r -p "Usuario SMB (${DOMAIN}\\...): " SMB_USER
  [ -n "$SMB_PASS" ] || { read -r -s -p "Contrasena SMB para ${DOMAIN}\\${SMB_USER}: " SMB_PASS; echo; }

  cat > "$creds_file" <<EOF
username=${SMB_USER}
password=${SMB_PASS}
domain=${DOMAIN}
EOF
  chmod 600 "$creds_file"

  msg "Montando //${server_ip}/${SHARE_NAME} -> ${MOUNT_POINT}"
  if ! mount -t cifs "//${server_ip}/${SHARE_NAME}" "$MOUNT_POINT" \
       -o "credentials=${creds_file},vers=3.1.1,sec=ntlmssp,uid=${uid_num},gid=${gid_num},iocharset=utf8,file_mode=0644,dir_mode=0755"; then
    mount -t cifs "//${server_ip}/${SHARE_NAME}" "$MOUNT_POINT" \
       -o "credentials=${creds_file},vers=3.0,sec=ntlmssp,uid=${uid_num},gid=${gid_num},iocharset=utf8,file_mode=0644,dir_mode=0755"
  fi

  fstab_line="//${server_ip}/${SHARE_NAME} ${MOUNT_POINT} cifs credentials=${creds_file},vers=3.1.1,sec=ntlmssp,uid=${uid_num},gid=${gid_num},iocharset=utf8,file_mode=0644,dir_mode=0755,x-systemd.automount,_netdev,noauto 0 0"
  grep -Fq "$fstab_line" /etc/fstab || echo "$fstab_line" >> /etc/fstab
  systemctl daemon-reload || true
  systemctl restart remote-fs.target || true

  ls -la "$MOUNT_POINT" || true
}

# ======================= EJECUCION =========================
msg "=== Teclado ==="
loadkeys "$KEYMAP" 2>/dev/null || true

msg "=== Detectando interfaz ==="
IFACE="${IFACE:-$(detect_iface)}"
[ -n "${IFACE:-}" ] || { msg "[ERR] No se encontro interfaz (en*/eth*)"; exit 1; }
msg "Usando: $IFACE"

chosen_server=""

# Perfil A
if [ "$PROFILE" = "A" ] || [ -z "$PROFILE" ]; then
  if apply_profile "$IFACE" "$A_IP_CIDR" "$A_GW" && test_connectivity "$A_SERVER_IP"; then
    msg "OK Perfil A (192.168.68.x)"
    chosen_server="$A_SERVER_IP"
  else
    msg "Fallo Perfil A"
  fi
fi

# Perfil B
if [ -z "$chosen_server" ] && { [ "$PROFILE" = "B" ] || [ -z "$PROFILE" ]; }; then
  if apply_profile "$IFACE" "$B_IP_CIDR" "$B_GW" && test_connectivity "$B_SERVER_IP"; then
    msg "OK Perfil B (192.168.1.x)"
    chosen_server="$B_SERVER_IP"
  else
    msg "Fallo Perfil B"
  fi
fi

[ -n "$chosen_server" ] || { msg "[ERR] Sin conectividad con ningun perfil"; ip route || true; exit 1; }

# Utilerias basicas (si hay red)
if command -v pacman >/dev/null 2>&1; then
  pacman -Syy --noconfirm || true
  pacman -Sy  --noconfirm archlinux-keyring || true
  pacman -Sy  --noconfirm git wget dos2unix archinstall || true
fi

# Montar SMB (opcional)
mount_smb "$chosen_server"

# Reporte final
msg ""
msg "Listo:"
msg " - Ruta por defecto:"
ip route | sed -n '1,3p' || true
msg " - Share: //${chosen_server}/${SHARE_NAME} -> ${MOUNT_POINT} (si cifs estaba disponible)"
