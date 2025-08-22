#!/usr/bin/env bash
set -euo pipefail

# txEdgeVM-setup.sh
# Arch minimal (IP prevista 10.99.64.2)
# Servicios:
#  - Unbound (resolver local) en 127.0.0.1:5335 (host network)
#  - AdGuard Home (DNS) en 0.0.0.0:53 -> upstream 127.0.0.1:5335
#  - Nginx Proxy Manager (80/81/443)
# Extras:
#  - nftables base
#  - tailscale habilitado (requiere 'tailscale up' luego)
#  - directorios de trabajo en /srv/edge

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Run as root."
    exit 1
  fi
}

pkg_install() {
  pacman -Sy --noconfirm --needed "$@"
}

require_root

echo "[*] Updating and installing packages..."
pacman -Syu --noconfirm
pkg_install podman podman-docker netavark aardvark-dns fuse-overlayfs slirp4netns \
           buildah skopeo nftables curl wget jq unzip tar nano tmux bash-completion \
           tailscale

echo "[*] Enabling nftables and tailscaled..."
systemctl enable --now nftables.service
systemctl enable --now tailscaled.service

# tailscale: autenticar luego con 'tailscale up' segun tu metodo (key o interactive)
# ejemplo: tailscale up --accept-routes --ssh

echo "[*] Creating directories..."
mkdir -p /srv/edge/{unbound,adguard,npm}
mkdir -p /srv/edge/unbound/{conf,logs}
mkdir -p /srv/edge/adguard/{conf,work,logs}
mkdir -p /srv/edge/npm/{data,letsencrypt}

# Unbound config
UNBOUND_CONF="/srv/edge/unbound/conf/unbound.conf"
if [ ! -f "$UNBOUND_CONF" ]; then
  cat >"$UNBOUND_CONF" <<'EOF'
server:
  verbosity: 1
  interface: 127.0.0.1
  port: 5335
  do-ip4: yes
  do-ip6: no
  do-udp: yes
  do-tcp: yes
  access-control: 127.0.0.0/8 allow
  hide-identity: yes
  hide-version: yes
  harden-glue: yes
  harden-dnssec-stripped: yes
  harden-referral-path: yes
  prefetch: yes
  qname-minimisation: yes
  aggressive-nsec: yes
  rrset-roundrobin: yes
  root-hints: "/etc/unbound/root.hints"
EOF
fi

# Root hints (best effort)
mkdir -p /etc/unbound
if curl -fsSL https://www.internic.net/domain/named.root -o /etc/unbound/root.hints; then
  echo "[*] Root hints downloaded."
else
  echo "[!] Could not fetch root.hints, continuing."
fi

echo "[*] Pulling images..."
podman pull docker.io/mvance/unbound:latest
podman pull docker.io/adguard/adguardhome:latest
podman pull docker.io/jc21/nginx-proxy-manager:latest

echo "[*] Writing systemd units..."
# Unbound (host network)
cat >/etc/systemd/system/edge-unbound.service <<'EOF'
[Unit]
Description=Unbound (container) - local resolver 127.0.0.1:5335
Wants=network-online.target
After=network-online.target

[Service]
Restart=always
TimeoutStartSec=0
ExecStartPre=-/usr/bin/podman rm -f edge-unbound
ExecStart=/usr/bin/podman run --name edge-unbound --network host \
  -v /srv/edge/unbound/conf:/opt/unbound/etc/unbound:Z \
  -v /srv/edge/unbound/logs:/var/log/unbound:Z \
  docker.io/mvance/unbound:latest
ExecStop=/usr/bin/podman stop -t 10 edge-unbound
ExecStopPost=-/usr/bin/podman rm -f edge-unbound

[Install]
WantedBy=multi-user.target
EOF

# AdGuard Home (host network) :53 + setup UI :3000
cat >/etc/systemd/system/edge-adguard.service <<'EOF'
[Unit]
Description=AdGuard Home (container) - DNS :53 and setup UI :3000
Wants=network-online.target
After=network-online.target
BindsTo=edge-unbound.service
After=edge-unbound.service

[Service]
Restart=always
TimeoutStartSec=0
ExecStartPre=-/usr/bin/podman rm -f edge-adguard
ExecStart=/usr/bin/podman run --name edge-adguard --network host \
  -v /srv/edge/adguard/conf:/opt/adguardhome/conf:Z \
  -v /srv/edge/adguard/work:/opt/adguardhome/work:Z \
  -v /srv/edge/adguard/logs:/opt/adguardhome/log:Z \
  --cap-add=NET_BIND_SERVICE \
  docker.io/adguard/adguardhome:latest
ExecStop=/usr/bin/podman stop -t 10 edge-adguard
ExecStopPost=-/usr/bin/podman rm -f edge-adguard

[Install]
WantedBy=multi-user.target
EOF

# AdGuard config base (si no existe) con upstream a 127.0.0.1:5335
AGH_YAML="/srv/edge/adguard/conf/AdGuardHome.yaml"
if [ ! -f "$AGH_YAML" ]; then
  cat >"$AGH_YAML" <<'EOF'
bind_host: 0.0.0.0
bind_port: 3000
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  upstream_dns:
    - 127.0.0.1:5335
  upstream_mode: parallel
  bootstrap_dns:
    - 1.1.1.1
    - 8.8.8.8
  protection_enabled: true
  local_domain_name: lan
tls:
  enabled: false
filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard Base
    id: 1
EOF
fi

# Nginx Proxy Manager (bridge, publica 80/81/443)
cat >/etc/systemd/system/edge-npm.service <<'EOF'
[Unit]
Description=Nginx Proxy Manager (container) - ports 80/81/443
Wants=network-online.target
After=network-online.target

[Service]
Restart=always
TimeoutStartSec=0
ExecStartPre=-/usr/bin/podman rm -f edge-npm
ExecStart=/usr/bin/podman run --name edge-npm --network bridge \
  -p 80:80 -p 81:81 -p 443:443 \
  -v /srv/edge/npm/data:/data:Z \
  -v /srv/edge/npm/letsencrypt:/etc/letsencrypt:Z \
  docker.io/jc21/nginx-proxy-manager:latest
ExecStop=/usr/bin/podman stop -t 10 edge-npm
ExecStopPost=-/usr/bin/podman rm -f edge-npm

[Install]
WantedBy=multi-user.target
EOF

echo "[*] nftables base policy..."
cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    ct state established,related accept
    iif lo accept
    tcp dport { 22, 53, 80, 81, 443, 3000 } accept
    udp dport { 53 } accept
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

echo "[*] Enabling services..."
systemctl daemon-reload
systemctl enable --now edge-unbound.service
systemctl enable --now edge-adguard.service
systemctl enable --now edge-npm.service

echo
echo "Done on txEdgeVM."
echo "- AdGuard first-run UI: http://<EDGE_IP>:3000  (configura y guarda; luego queda solo DNS :53)"
echo "- NPM admin:           http://<EDGE_IP>:81"
echo "- DNS listo en :53 (AdGuard -> Unbound 127.0.0.1:5335)."
echo "- Recuerda: tailscale up"
