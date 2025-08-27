# Reemplaza tu apply_profile() por esta
strip_cr() { printf "%s" "$1" | tr -d '\r'; }
is_ipv4() { printf "%s" "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; }

apply_dns() {
  printf "nameserver %s\nnameserver %s\n" "$DNS1" "$DNS2" > /etc/resolv.conf
}

flush_iface() {
  dev="$1"
  ip addr flush dev "$dev" || true
  ip route flush dev "$dev" || true
  ip neigh flush dev "$dev" || true
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

  if [ -z "$gw" ] || ! is_ipv4 "$gw"; then
    echo "[ERR] Gateway invalido: '$gw'"; return 1
  fi

  echo ">>> Perfil: IP=$ip_cidr GW=$gw en $dev"
  flush_iface "$dev"
  ip addr replace "$ip_cidr" dev "$dev"
  apply_dns

  # Reemplazar SIEMPRE la ruta por defecto por la del perfil
  ip route del default >/dev/null 2>&1 || true
  ip route add default via "$gw" dev "$dev"

  # Esperar a que el GW responda
  if ! wait_gw "$gw"; then
    echo "[ERR] El gateway $gw no responde"; return 1
  fi

  # Verificacion dura: la ruta a 1.1.1.1 debe ser via <gw> dev <dev>
  if ! ip route get 1.1.1.1 2>/dev/null | grep -q "via $gw .* dev $dev"; then
    echo "[ERR] La ruta por defecto NO quedo via $gw en $dev"
    ip route || true
    return 1
  fi

  # Mostrar estado final
  ip -br addr show "$dev" || true
  ip route | sed -n '1,5p' || true
  return 0
}
