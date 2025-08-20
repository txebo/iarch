#!/usr/bin/env bash
set -euo pipefail

# === VARIABLES DEL SISTEMA ===

DISK="/dev/sda"
HOSTNAME="archvm"
USERNAME="user"
ROOT_PASSWORD="root"
USER_PASSWORD="user"

LOCALE="en_US.UTF-8"
KEYMAP="la-latin1"
TIMEZONE="America/Monterrey"

# IP estatica esperada por switch vPrivado (ajusta si es necesario)
STATIC_IP="10.99.64.10/24"
GATEWAY="10.99.64.1"
DNS="1.1.1.1"
IFACE_NAME="eth0"

# Archivo de paquetes adicionales
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"

# === PARTICIONES Y FORMATO ===

echo "Formateando disco $DISK..."
wipefs -af "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1::+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:: -t 2:8300 -c 2:"ROOT" "$DISK"

EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# === INSTALACION BASE ===

echo "Instalando sistema base..."
pacstrap -K /mnt base linux linux-firmware

# Instalar paquetes adicionales si existen
if [ -f "$PKG_LIST" ]; then
    echo "Instalando paquetes adicionales desde $PKG_LIST..."
    pacstrap -K /mnt $(grep -v '^#' "$PKG_LIST" | xargs)
fi

# === CONFIGURACION DEL SISTEMA ===

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -e <<EOF

# Locales y zona horaria
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Hostname y red
echo "$HOSTNAME" > /etc/hostname
cat <<EOL > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
EOL

# Configuracion de red estatica con systemd-networkd
cat <<EOL > /etc/systemd/network/20-wired.network
[Match]
Name=$IFACE_NAME

[Network]
Address=$STATIC_IP
Gateway=$GATEWAY
DNS=$DNS
IPv6AcceptRA=no
EOL

systemctl enable systemd-networkd
systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Usuario root y usuario normal
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# Bootloader systemd-boot
bootctl install
cat <<EOL > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value $ROOT_PART) rw
EOL

cat <<EOL > /boot/loader/loader.conf
default arch
timeout 3
editor no
EOL

EOF

echo "Instalacion finalizada. Puedes reiniciar la maquina."
