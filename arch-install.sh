#!/usr/bin/env bash
set -euo pipefail

# =============================
# Arch automated base install (modificado)
# =============================

DISK="/dev/sda"
HOSTNAME="archvm"
USERNAME="user"
ROOT_PASSWORD="root"
USER_PASSWORD="user"

LOCALE="en_US.UTF-8"
KEYMAP="la-latin1"
TIMEZONE="America/Monterrey"

# Red privada
IFACE_NAME="e*"
STATIC_IP="10.99.64.10/24"
GATEWAY="10.99.64.1"
DNS="1.1.1.1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"

if [ ! -b "$DISK" ]; then
  echo "ERROR: disk $DISK not found."
  exit 1
fi

wipefs -af "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1::+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:: -t 2:8300 -c 2:"ROOT" "$DISK"

EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

pacstrap -K /mnt base linux linux-firmware vim sudo

if [ -f "$PKG_LIST" ]; then
  mapfile -t EXTRA_PKGS < <(
    sed 's/#.*$//' "$PKG_LIST" | tr -d '\r' | awk 'NF==1 {print $1}'
  )
  if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then
    pacstrap -K /mnt "${EXTRA_PKGS[@]}"
  fi
fi

genfstab -U /mnt >> /mnt/etc/fstab

ROOT_UUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"

arch-chroot /mnt /bin/bash -e <<CHROOT_EOF
set -euo pipefail

echo "${LOCALE} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

echo "${HOSTNAME}" > /etc/hostname
cat >/etc/hosts <<EOT
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOT

mkdir -p /etc/systemd/network
cat >/etc/systemd/network/20-wired.network <<EOT
[Match]
Name=${IFACE_NAME}

[Network]
Address=${STATIC_IP}
Gateway=${GATEWAY}
DNS=${DNS}
IPv6AcceptRA=no
EOT

systemctl enable systemd-networkd
systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo "root:${ROOT_PASSWORD}" | chpasswd
useradd -m -G wheel -s /bin/bash "${USERNAME}" || true
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

pacman -Sy --noconfirm intel-ucode || pacman -Sy --noconfirm amd-ucode || true

bootctl install
cat >/boot/loader/entries/arch.conf <<EOT
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=${ROOT_UUID} rw
EOT

cat >/boot/loader/entries/arch-fallback.conf <<EOT
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=PARTUUID=${ROOT_UUID} rw
EOT

cat >/boot/loader/loader.conf <<EOT
default arch
timeout 3
editor no
EOT

systemctl enable sshd
CHROOT_EOF

echo "Install complete. You may reboot now."
