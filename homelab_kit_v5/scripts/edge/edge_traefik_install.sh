#!/usr/bin/env bash
set -euo pipefail
require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "run as root"; exit 1; }; }
require_root
mkdir -p /srv/edge/traefik/{conf,logs}
cat >/srv/edge/traefik/conf/traefik_static.yml <<'EOF'
entryPoints:
  web:
    address: ":80"
api:
  dashboard: true
providers:
  file:
    directory: "/srv/edge/traefik/conf"
    watch: true
EOF
cat >/srv/edge/traefik/conf/traefik_dynamic.yml <<'EOF'
http:
  routers:
    stash:
      rule: "Host(`stash.media-share.online`)"
      service: stash
    downloads:
      rule: "Host(`downloads.media-share.online`)"
      service: downloads
  services:
    stash:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:9999"
    downloads:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8081"
EOF
cat >/etc/systemd/system/edge-traefik.service <<'EOF'
[Unit]
Description=Traefik (container) - :80
After=network-online.target
Wants=network-online.target
[Service]
Restart=always
TimeoutStartSec=0
ExecStartPre=-/usr/bin/podman rm -f edge-traefik
ExecStart=/usr/bin/podman run --name edge-traefik --network host   -v /srv/edge/traefik/conf:/etc/traefik:Z   -v /srv/edge/traefik/logs:/var/log/traefik:Z   docker.io/library/traefik:latest   --configFile=/etc/traefik/traefik_static.yml
ExecStop=/usr/bin/podman stop -t 10 edge-traefik
ExecStopPost=-/usr/bin/podman rm -f edge-traefik
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now edge-traefik.service
echo "done."
