#!/usr/bin/env sh
# snet.sh — teclado, red (dos perfiles), utilerías y SMB
# Funciona en live ISO sin dos2unix ni bash features.

# --- Autolimpieza CRLF/BOM y re-ejecución ---
case "$(head -c3 "$0" | od -An -t x1 | tr -d ' ')" in
  efbbbf) t="$(mktemp)"; tail -c +4 "$0" >"$t"; chmod +x "$t"; exec "$t" "$@";;
esac
if grep -q "$(printf '\r')" "$0" 2>/dev/null; then
  t="$(mktemp)"; tr -d '\r' <"$0" >"$t"; chmod +x "$t"; exec "$t" "$@"
fi

set -eu

# ===================== CONFIG =====================
KEYMAP="${KEYMAP:-la-latin1}"

# Perfil A (LAN 192.168.68.0/24)
A_IP_CIDR="${A_IP_CIDR:-192.168.68.20/24}"
A_GW="${A_GW:-192.168.68.1}"
A_SERVER_IP="${A_SERVER_IP:-192.168.68.128}"

# Perfil B (LAN 192.168.1.0/24)
B_IP_CIDR="${B_IP_CIDR:-192.168.1.20/24}"
B_GW="${B_GW:-192.168.1.1}"
B_SERVER_IP="${B_SERVER_IP:-192.168.1.67}"

# SMB
SERVER_NAME="${SERVER_NAME:-Neural-TXIA}"
SHARE_NAME="${SHARE_NAME:-shared}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/shared}"
DOMAIN="${DOMAIN:-Neural-TXIA}"
SMB_USER="${SMB_USER:-smbtxvm}"
SMB_PASS="${SMB_PASS:-}"          # si vacío, se pedirá
PROFILE="${PROFILE:-}"            # A o B para forzar

# DNS para el live
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"

# ==================== HELPERS =====================
msg() { printf "%s\n" "$*"; }
strip_cr(){ printf "%s" "$1" | tr -d '\r'; }
is_ipv4(){ printf "%s" "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; }

detect_iface() {
  ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(en|eth|eno|ens|enp)' | head -n1 ||
  ip -o link show    2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(en|eth|eno|ens|enp)' | head -n1 || true
}

apply_dns(){ printf "nameserver %s\nnameserver %s\n" "$DNS1" "$DNS2" > /etc/resolv.conf || true; }

flush_iface(){
  d="$1"
  ip addr flush dev "$d" 2>/dev/null || true
  ip route flush dev "$d" 2>/dev/null || true
  ip neigh flush dev "$d" 2>/dev/null || true
  ip link set "$d" up
}

wait_gw(){
  gw="$1"; tries=0
  while :; do
    ping -c1 -W1 "$gw" >/dev/null 2>&1 && return 0
    tries=$((tries+1)); [ "$tries" -ge 10 ] && return 1
    sleep 1
  done
}

apply_profile(){
  dev="$1"; ip_cidr="$(strip_cr "$2")"; gw="$(strip_cr "$3")"
  [ -n "$gw" ] && is_ipv4 "$gw" || { msg "[ERR] Gateway inválido: '$gw'"; return 1; }

  msg ">>> Aplico perfil: IP=$ip_cidr  GW=$gw  IFACE=$dev"
  flush_iface "$dev"
  ip addr replace "$ip_cidr" dev "$dev"
  apply_dns

  ip route del default >/dev/null 2>&1 || true
  ip route add default via "$gw" dev "$dev"

  if ! wait_gw "$gw"; then msg "[ERR] Gateway $gw no responde"; return 1; fi

  if ! ip route get 1.1.1.1 2>/dev/null | grep -q "via $gw .* dev $dev"; then
    msg "[ERR] Default route NO quedó via $gw en $dev"; ip route || true; return 1
  fi

  ip -br addr show "$dev" || true
  ip route | sed -n '1,5p' || true
  return 0
}

test_connectivity(){
  host="$(strip_cr "$1")"; ok=0
  ping -c1 -W2 1.1.1.1       >/dev/null 2>&1 && ok=$((ok+1))
  ping -c1 -W2 archlinux.org >/dev/null 2>&1 && ok=$((ok+1))
  ping -c1 -W2 "$host"       >/dev/null 2>&1 && ok=$((ok+1))
  [ "$ok" -ge 2 ]
}

mount_smb(){
  host="$1"
  [ -x /usr/bin/mount.cifs ] || { command -v pacman >/dev/null 2>&1 && pacman -Sy --noconfirm cifs-utils || true; }
  [ -x /usr/bin/mount.cifs ] || { msg "[WARN] cifs-utils no disponible; omito montaje"; return 0; }

  real="${SUDO_USER:-$USER}"; uid="$(id -u "$real")"; gid="$(id -g "$real")"
  mkdir -p "$MOUNT_POINT"
  mkdir -p /etc/cifs-creds; chmod 700 /etc/cifs-creds
  cred="/etc/cifs-creds/${SERVER_NAME}_${SHARE_NAME}.cred"

  [ -n "$SMB_USER" ] || read -r -p "Usuario SMB (${DOMAIN}\\...): " SMB_USER
  [ -n "$SMB_PASS" ] || { read -r -s -p "Contraseña SMB para ${DOMAIN}\\${SMB_USER}: " SMB_PASS; echo; }

  cat > "$cred" <<EOF
username=${SMB_USER}
password=${SMB_PASS}
domain=${DOMAIN}
EOF
  chmod 600 "$cred"

  msg "Montando //${host}/${SHARE_NAME} -> ${MOUNT_POINT}"
  mount -t cifs "//${host}/${SHARE_NAME}" "$MOUNT_POINT" \
    -o "credentials=${cred},vers=3.1.1,sec=ntlmssp,uid=${uid},gid=${gid},iocharset=utf8,file_mode=0644,dir_mode=0755" \
  || mount -t cifs "//${host}/${SHARE_NAME}" "$MOUNT_POINT" \
    -o "credentials=${cred},vers=3.0,sec=ntlmssp,uid=${uid},gid=${gid},iocharset=utf8,file_mode=0644,dir_mode=0755"

  line="//${host}/${SHARE_NAME} ${MOUNT_POINT} cifs credentials=${cred},vers=3.1.1,sec=ntlmssp,uid=${uid},gid=${gid},iocharset=utf8,file_mode=0644,dir_mode=0755,x-systemd.automount,_netdev,noauto 0 0"
  grep -Fq "$line" /etc/fstab || echo "$line" >> /etc/fstab
  systemctl daemon-reload || true
  systemctl restart remote-fs.target || true

  ls -la "$MOUNT_POINT" || true
}

# ==================== EJECUCIÓN =====================
msg "=== Teclado ==="; loadkeys "$KEYMAP" 2>/dev/null || true

msg "=== Detectando interfaz ==="
IFACE="${IFACE:-$(detect_iface)}"
[ -n "${IFACE:-}" ] || { msg "[ERR] Sin NIC (en*/eth*)"; exit 1; }
msg "Usando: $IFACE"

chosen=""

# Intentar Perfil A (68.x) salvo que se fuerce B
if [ "$PROFILE" = "A" ] || [ -z "$PROFILE" ]; then
  if apply_profile "$IFACE" "$A_IP_CIDR" "$A_GW" && test_connectivity "$A_SERVER_IP"; then
    msg "OK Perfil A"; chosen="$A_SERVER_IP"
  else
    msg "Fallo Perfil A"
  fi
fi

# Intentar Perfil B (1.x) si A no quedó
if [ -z "$chosen" ] && { [ "$PROFILE" = "B" ] || [ -z "$PROFILE" ]; }; then
  if apply_profile "$IFACE" "$B_IP_CIDR" "$B_GW" && test_connectivity "$B_SERVER_IP"; then
    msg "OK Perfil B"; chosen="$B_SERVER_IP"
  else
    msg "Fallo Perfil B"
  fi
fi

[ -n "$chosen" ] || { msg "[ERR] Sin conectividad en A ni B"; ip route || true; exit 1; }

# Utilerías básicas (si hay red)
command -v pacman >/dev/null 2>&1 && {
  pacman -Syy --noconfirm || true
  pacman -Sy  --noconfirm archlinux-keyring || true
  pacman -Sy  --noconfirm git wget dos2unix archinstall || true
}

# Montaje SMB
mount_smb "$chosen"

msg ""; msg "Listo:"
msg " - Default route:"; ip route | sed -n '1,3p' || true
msg " - Share: //${chosen}/${SHARE_NAME} -> ${MOUNT_POINT} (si cifs disponible)"
