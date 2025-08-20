#!/usr/bin/env bash
set -euo pipefail

# =============================
# Arch automated base install
# =============================
# This script:
# - Does NOT modify live ISO env (mirrors, keymap, network)
# - Partitions and formats target disk (EFI + root)
# - Installs Arch base (en_US)
# - Reads extra packages from packages.x86_64 in same folder
# - Configures keyboard, timezone, hostname
# - Preconfigures static network with systemd-networkd for vPrivado
# - Installs systemd-boot
#
# Adjust variables as needed.

# ---- User variables ----
DISK="/dev/sda"
HOSTNAME="archvm"
USERNAME="user"
ROOT_PASSWORD="root"
USER_PASSWORD="user"

LOCALE="en_US.UTF-8"
KEYMAP="la-latin1"
TIMEZONE="America/Monterrey"

# vPrivado network settings
IFACE_NAME="eth0"
STATIC_IP="10.99.64.10/24"
GATEWAY="10.99.64.1"
DNS="1.1.1.1"

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"

# ---- Safety checks ----
if [ ! -b "$DISK" ]; then
  echo "ERROR: disk $DISK not found."
  exit 1
fi

# ---- Partitioning (EFI + root) ----
echo "Partitioning $DISK ..."
wipefs -af "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1::+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:: -t 2:8300 -c 2:"ROOT" "$DISK"

EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"

# ---- Filesystems ----
echo "Creating filesystems ..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

# ---- Mount target ----
echo "Mounting target ..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ---- Base install ----
echo "Installing base system ..."
pacstrap -K /mnt base linux linux-firmware

# ---- Extra packages from packages.x86_64 (optional) ----
# File format:
#   one package name per line
#   lines starting with # are comments
#   no headings, no spaces
if [ -f "$PKG_LIST" ]; then
  echo "Reading extra packages from $PKG_LIST ..."
  # Sanitize and validate
  mapfile -t EXTRA_PKGS < <(
    sed 's/#.*$//' "$PKG_LIST" \
    | tr -d '\r' \
    | awk 'NF==1 {print $1}'
  )

  if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then
    echo "Validating package names ..."
    BAD=0
    for pkg in "${EXTRA_PKGS[@]}"; do
      if ! pacman -Si "$pkg" >/dev/null 2>&1; then
        echo "Package not found: $pkg"
        BAD=1
      fi
    done
    if [ "$BAD" -ne 0 ]; then
      echo "ERROR: invalid package names detected. Fix $PKG_LIST and rerun."
      exit 1
    fi

    echo "Installing extra packages: ${EXTRA_PKGS[*]}"
    pacstrap -K /mnt "${EXTRA_PKGS[@]}"
  fi
else
  echo "No packages.x86_64 found. Skipping extra packages."
fi

# ---- Fstab ----
genfstab -U /mnt >> /mnt/etc/fstab

# ---- Values needed inside chroot ----
ROOT_UUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"

# ---- System configuration in chroot ----
arch-chroot /mnt /bin/bash -e <<'CHROOT_EOF'
set -euo pipefail
CHROOT_EOF

# Re-enter chroot with exported vars
export LOCALE KEYMAP TIMEZONE HOSTNAME USERNAME ROOT_PASSWORD USER_PASSWORD
export IFACE_NAME STATIC_IP GATEWAY DNS ROOT_UUID

arch-chroot /mnt /bin/bash -e <<'CHROOT_EOF'
set -euo pipefail

# Locales
echo "${LOCALE} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Console keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Timezone and clock
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Hostname and hosts
echo "${HOSTNAME}" > /etc/hostname
cat >/etc/hosts <<EOT
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOT

# Network: systemd-networkd static config for vPrivado
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

# Users and sudo
echo "root:${ROOT_PASSWORD}" | chpasswd
useradd -m -G wheel -s /bin/bash "${USERNAME}" || true
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# Bootloader: systemd-boot
bootctl install
cat >/boot/loader/entries/arch.conf <<EOT
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=${ROOT_UUID} rw
EOT

cat >/boot/loader/loader.conf <<EOT
default arch
timeout 3
editor no
EOT
CHROOT_EOF

echo "Install complete. You may reboot now."
