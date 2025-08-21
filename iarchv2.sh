#!/usr/bin/env bash
set -euo pipefail

# arch-install-uefi-strict.sh
# Arch installer for Hyper-V Gen2 (UEFI) that FAILS on any critical issue.
# It verifies UEFI, network, ESP mount, systemd-boot install, UEFI fallback,
# loader entries, PARTUUID, kernel/initramfs and fstab.
# WARNING: destroys the target disk.

# ---------------- Config ----------------
DISK="/dev/sda"

HOSTNAME="archvm"
USERNAME="user"
ROOT_PASSWORD="root"
USER_PASSWORD="user"

LOCALE="en_US.UTF-8"
KEYMAP="la-latin1"
TIMEZONE="America/Monterrey"

# Network for installed system (systemd-networkd, static)
IFACE_MATCH="e*"
STATIC_IP="10.99.64.10/24"
GATEWAY="10.99.64.1"
DNS="1.1.1.1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"

# -------------- Helpers -----------------
ok()   { printf "[OK] %s\n" "$*"; }
bad()  { printf "[!!] %s\n" "$*" >&2; }
die()  { bad "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# -------------- Preflight ---------------
echo "== PRE-FLIGHT =="
[ -d /sys/firmware/efi ] || die "UEFI not detected. Use Hyper-V Gen2 (UEFI) and disable Secure Boot."
ok "UEFI firmware present"

[ -b "$DISK" ] || die "Disk $DISK not found"
ok "Target disk $DISK present"

if mount | grep -qE " on /mnt( |$)"; then
  die "/mnt is mounted. Run: umount -R /mnt and retry."
fi

for c in pacman pacstrap sgdisk mkfs.fat mkfs.ext4 blkid arch-chroot findmnt; do
  need "$c"
done
ok "Required tools found"

ping -c1 archlinux.org >/dev/null 2>&1 || die "No network connectivity. Run snet.sh first."
ok "Network ready"

# ---------- Partitioning/FS -------------
echo "== PARTITION AND FS =="
wipefs -af "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"
EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"
ok "GPT created: $EFI_PART (ESP), $ROOT_PART (ROOT)"

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
ok "Filesystems created"

mkdir -p /mnt
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# Must be FAT32 on /mnt/boot
findmnt -no FSTYPE,TARGET /mnt/boot | grep -qi "vfat.*\/mnt\/boot" || die "/mnt/boot is not a FAT32 ESP. Mount the EFI partition at /mnt/boot."
ok "ESP mounted at /mnt/boot"

# ------------- Base install -------------
echo "== BASE INSTALL =="
pacstrap -K /mnt base linux linux-firmware sudo vim

if [ -f "$PKG_LIST" ]; then
  mapfile -t EXTRA_PKGS < <(sed 's/#.*$//' "$PKG_LIST" | tr -d '\r' | awk 'NF==1 {print $1}')
  if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then
    pacstrap -K /mnt "${EXTRA_PKGS[@]}"
    ok "Extra packages installed: ${EXTRA_PKGS[*]}"
  fi
fi

genfstab -U /mnt >> /mnt/etc/fstab
grep -E ' / (ext4|btrfs|xfs) ' /mnt/etc/fstab >/dev/null 2>&1 || die "fstab missing root mount after genfstab"
ok "fstab generated"

ROOT_UUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"
[ -n "$ROOT_UUID" ] || die "Could not read PARTUUID for $ROOT_PART"

# -------- Configure inside chroot --------
echo "== CONFIGURE IN CHROOT =="
arch-chroot /mnt /bin/bash -eu <<CHROOT_EOF
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
Name=${IFACE_MATCH}

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
id "${USERNAME}" >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

if grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
  pacman -Sy --noconfirm intel-ucode || true
elif grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
  pacman -Sy --noconfirm amd-ucode || true
fi

mkinitcpio -P

bootctl --path=/boot install

UCODE_LINE=""
[ -f /boot/intel-ucode.img ] && UCODE_LINE="initrd  /intel-ucode.img"
[ -f /boot/amd-ucode.img ]   && UCODE_LINE="initrd  /amd-ucode.img"

mkdir -p /boot/loader/entries
cat >/boot/loader/entries/arch.conf <<EOT
title   Arch Linux
linux   /vmlinuz-linux
${UCODE_LINE}
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

systemctl enable sshd || true
CHROOT_EOF

# --------- UEFI fallback (critical) -----
echo "== UEFI FALLBACK =="
mkdir -p /mnt/boot/EFI/BOOT
[ -f /mnt/boot/EFI/systemd/systemd-bootx64.efi ] || die "systemd-bootx64.efi missing from ESP"
cp -f /mnt/boot/EFI/systemd/systemd-bootx64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI
[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ] || die "Failed to create fallback BOOTX64.EFI"
ok "Fallback BOOTX64.EFI present"

# ------------- Postflight checks --------
echo "== POST-FLIGHT VALIDATION =="

[ -f /mnt/boot/vmlinuz-linux ]       || die "Missing /boot/vmlinuz-linux"
[ -f /mnt/boot/initramfs-linux.img ] || die "Missing /boot/initramfs-linux.img"
ok "Kernel and initramfs present"

[ -f /mnt/boot/loader/loader.conf ]               || die "Missing /boot/loader/loader.conf"
[ -f /mnt/boot/loader/entries/arch.conf ]         || die "Missing /boot/loader/entries/arch.conf"
grep -q "root=PARTUUID=${ROOT_UUID}" /mnt/boot/loader/entries/arch.conf || die "arch.conf PARTUUID mismatch"
ok "Loader entries OK"

# Sanity: ensure ESP is still mounted and FAT
findmnt -no FSTYPE,TARGET /mnt/boot | grep -qi "vfat.*\/mnt\/boot" || die "ESP not mounted or wrong FS at /mnt/boot"
ok "ESP still correct"

# Optional: quick ping from target (not fatal if isolated)
if arch-chroot /mnt ping -c1 archlinux.org >/dev/null 2>&1; then
  ok "Target can resolve/ping archlinux.org"
else
  echo "[*] Target ping failed (not fatal if network is private on first boot)"
fi

echo
echo "=== INSTALLATION PASS: Ready to reboot ==="
echo "Run: umount -R /mnt ; reboot (remove ISO). Ensure Secure Boot is disabled."
