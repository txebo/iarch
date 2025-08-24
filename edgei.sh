# A1) Paquetes base del edge
pacman -S --noconfirm linux-lts linux-firmware hyperv \
  podman podman-docker podman-compose netavark aardvark-dns \
  ca-certificates curl jq

# A2) Servicios de integracion Hyper-V (solo se habilitan)
systemctl enable hv_kvp_daemon.service
systemctl enable hv_vss_daemon.service
# opcional: file copy de Hyper-V
cat >/etc/systemd/system/hv_fcopy_uio_daemon.service <<'EOF'
[Unit]
Description=Hyper-V File Copy Service
After=network.target
[Service]
ExecStart=/usr/bin/hv_fcopy_uio_daemon
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl enable hv_fcopy_uio_daemon.service

# A3) Bootloader systemd-boot (UEFI Gen2)
bootctl install
ROOTDEV="$(findmnt -no SOURCE /)"; UUID="$(blkid -s UUID -o value "$ROOTDEV")"
cat >/boot/loader/entries/arch-lts.conf <<EOF
title   Arch Linux (LTS)
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img
options root=UUID=$UUID rw
EOF
cat >/boot/loader/loader.conf <<'EOF'
default arch-lts.conf
timeout 2
editor no
EOF

# A4) Red persistente (txedgevm = 10.99.64.2, MAC 56:a8:ea:fa:4b:23)
mkdir -p /etc/udev/rules.d /etc/systemd/network
echo 'SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="56:a8:ea:fa:4b:23", NAME="lan0"' > /etc/udev/rules.d/10-net-names.rules
cat >/etc/systemd/network/10-lan0.network <<'EOF'
[Match]
Name=lan0
[Network]
Address=10.99.64.2/24
Gateway=10.99.64.1
DNS=1.1.1.1
EOF
systemctl enable systemd-networkd systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# A5) Usuario de servicio para contenedores (rootless)
id edge >/dev/null 2>&1 || useradd -m -s /bin/bash edge
# Como estas en chroot, no uses loginctl. Marca linger creando el archivo:
mkdir -p /var/lib/systemd/linger
touch /var/lib/systemd/linger/edge

# A6) Arbol de Traefik listo (solo archivos, sin arrancar nada)
install -o edge -g edge -d /home/edge/edge-stack/traefik/dynamic
install -o edge -g edge -d /home/edge/edge-stack/traefik/logs

cat >/home/edge/edge-stack/traefik/traefik.yml <<'EOF'
entryPoints:
  web:
    address: ":80"
providers:
  file:
    directory: "/home/edge/edge-stack/traefik/dynamic"
    watch: true
accessLog:
  filePath: "/home/edge/edge-stack/traefik/logs/access.log"
log:
  level: INFO
EOF
chown edge:edge /home/edge/edge-stack/traefik/traefik.yml

# backends que enruta traefik (se sirven desde txbkendvm)
cat >/home/edge/edge-stack/traefik/dynamic/stash.yml <<'EOF'
http:
  routers:
    stash:
      rule: "Host(`stash.media-share.online`)"
      entryPoints: ["web"]
      service: "stash"
  services:
    stash:
      loadBalancer:
        servers:
          - url: "http://10.99.64.10:9999"
EOF

cat >/home/edge/edge-stack/traefik/dynamic/downloads.yml <<'EOF'
http:
  routers:
    downloads:
      rule: "Host(`downloads.media-share.online`)"
      entryPoints: ["web"]
      service: "downloads"
  services:
    downloads:
      loadBalancer:
        servers:
          - url: "http://10.99.64.10:8081"
EOF
chown -R edge:edge /home/edge/edge-stack
