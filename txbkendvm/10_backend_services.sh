#!/usr/bin/env bash
set -euo pipefail

BASE="/srv/backend"
MEDIA="/srv/media/stash"   # SMB mount from Windows host

# Prepare dirs
mkdir -p "${BASE}/stash" "${BASE}/downloads"
# Ensure media mount exists (warn if not mounted yet)
if ! mountpoint -q "${MEDIA}"; then
  echo "WARN: ${MEDIA} is not a mountpoint. Check SMB mount/fstab."
fi

# Stash: keep config in host, media library in ${MEDIA}
# Web UI will run initial setup; point Library path to /data
podman rm -f stash 2>/dev/null || true
podman run -d --name stash \
  -p 9999:9999 \
  -v "${BASE}/stash:/root/.stash" \
  -v "${MEDIA}:/data" \
  --restart=unless-stopped \
  docker.io/stashapp/stash:latest

# Filebrowser serving downloads workspace (separate from USB)
podman rm -f downloads 2>/dev/null || true
podman run -d --name downloads \
  -p 8081:80 \
  -v "${BASE}/downloads:/srv" \
  --restart=unless-stopped \
  docker.io/filebrowser/filebrowser:latest

podman ps
