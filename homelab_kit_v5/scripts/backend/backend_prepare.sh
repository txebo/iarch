#!/usr/bin/env bash
set -euo pipefail
require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "run as root"; exit 1; }; }
pkg(){ pacman -Sy --noconfirm --needed "$@" || true; }
require_root
pacman -Syu --noconfirm || true
pkg podman netavark aardvark-dns fuse-overlayfs slirp4netns buildah skopeo nftables cifs-utils jq
systemctl enable --now nftables.service
mkdir -p /srv/{containers,data,logs}
echo "done."
