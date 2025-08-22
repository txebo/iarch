#!/usr/bin/env bash
set -euo pipefail

# txBkendVM-setup.sh
# Arch XFCE (IP prevista 10.99.64.10)
# Objetivo: instalar paquetes base, nftables y preparar carpetas. SIN servicios.

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Run as root."
    exit 1
  fi
}

pkg_install() {
  pacman -Sy --noconfirm --needed "$@"
}

owner_user() {
  if id -u tx >/dev/null 2>&1; then
    echo "tx"
  else
    echo "root"
  fi
}

require_root

echo "[*] Updating and installing packages..."
pacman -Syu --noconfirm
pkg_install podman netavark aardvark-dns fuse-overlayfs slirp4netns \
           buildah skopeo cifs-utils git curl wget jq unzip tar \
           nano tmux bash-completion reflector pacman-contrib nftables

echo "[*] Enabling nftables..."
systemctl enable --now nftables.service

echo "[*] Creating folder structure under /srv ..."
mkdir -p /srv/{containers,data,logs}
mkdir -p /srv/containers/{projects,volumes,compose}
mkdir -p /srv/data/{db,files,backup}
mkdir -p /srv/logs/{system,apps}

OWN="$(owner_user)"
chown -R "$OWN":"$OWN" /srv || true

echo "[*] nftables base policy (allow ssh)..."
cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    ct state established,related accept
    iif lo accept
    tcp dport { 22 } accept
    icmp type echo-request accept
    counter drop
  }
  chain forward {
    type filter hook forward priority 0;
    ct state established,related accept
    counter drop
  }
  chain output {
    type filter hook output priority 0;
    accept
  }
}
EOF
systemctl reload nftables.service || systemctl restart nftables.service

echo
echo "Done on txBkendVM."
echo "- Carpetas listas en /srv (containers, data, logs)."
echo "- Podman instalado (root/rootless disponible)."
echo "- Sin servicios desplegados (como solicitaste: solo folders)."
