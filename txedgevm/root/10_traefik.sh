#!/usr/bin/env bash
set -euo pipefail

BASE="/srv/edge/traefik"
mkdir -p "$BASE"/{acme,logs}
chmod 700 "$BASE"/acme

cat >"$BASE/traefik.yml" <<'EOF'
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

api:
  dashboard: true

providers:
  file:
    filename: /etc/traefik/dyn.yml
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@example.local
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

cat >"$BASE/dyn.yml" <<'EOF'
http:
  routers:
    stash:
      rule: "Host(`stash.local`)"
      entryPoints: ["web"]
      service: stash_svc
    downloads:
      rule: "Host(`downloads.local`)"
      entryPoints: ["web"]
      service: downloads_svc
  services:
    stash_svc:
      loadBalancer:
        servers:
          - url: "http://10.99.64.10:9999"
    downloads_svc:
      loadBalancer:
        servers:
          - url: "http://10.99.64.10:8081"
EOF

cat >"$BASE/podman-compose.yml" <<'EOF'
version: "3.8"
services:
  traefik:
    image: docker.io/library/traefik:latest
    command:
      - "--providers.file.filename=/etc/traefik/dyn.yml"
      - "--api.insecure=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dyn.yml:/etc/traefik/dyn.yml:ro
      - ./acme:/letsencrypt
      - ./logs:/logs
    restart: unless-stopped
EOF

cd "$BASE"
podman-compose up -d
podman ps

# opcional: generar servicio systemd para autoinicio
if command -v podman >/dev/null 2>&1; then
  if podman ps --format '{{.Names}}' | grep -q '^traefik$'; then
    podman generate systemd --name --files traefik
    if [ -f container-traefik.service ]; then
      sudo mv container-traefik.service /etc/systemd/system/
      sudo systemctl enable --now container-traefik.service
    fi
  fi
fi
