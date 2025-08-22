#!/usr/bin/env bash
set -euo pipefail

# iarchv4.sh — Arch installer (Hyper-V Gen2 UEFI, Secure Boot OFF)
# Falla en cuanto detecta un problema crítico.

# -------- Config --------
DISK="/dev/sda"

HOSTNAME="txPruebasVM"
USERNAME="tx"
ROOT_PASSWORD="root"
USER_PASSWORD="user"

LOCALE="en_US.UTF-8"
KEYMAP="la-latin1"
TIMEZONE="America/Monterrey"

# Red estática para el sistema instalado (systemd-networkd)
IFACE_MATCH="e*"
STATIC_IP="10.99.64.10/24"
GATEWAY="10.99.64.1"
DNS="1.1.1.1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"

# -------- Helpers --------
ok()  { printf "[OK] %s\n" "$*"; }
die() { printf "[!!] %s\n" "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

net_ok() {
  # Usar dominios accesibles en tu red
  if command -v curl >/dev/null 2>&1; then
    curl -fsSIL --max-time 8 https://github.com/ >/dev/null 2>&1 && return 0
    curl -fsSIL --max-time 8 https://raw.githubusercontent.com/ >/dev/null 2>&1 && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q --spider --timeout=8 https://github.com/ && return 0
    wget -q --spider --timeout=8 https://raw.githubusercontent.com/ && return 0
  fi
  timeout 6 bash -c '>/dev/tcp/github.com/443' 2>/dev/null && return 0
  timeout 6 bash -c '>/dev/tcp/raw.githubusercontent.com/443' 2>/dev/null && return 0
  return 1
}

# -------- Pre-flight --------
echo "== PRE-FLIGHT =="
[ -d /sys/firmware/efi ] || die "UEFI not detected. Use Hyper-V Gen2 (UEFI) and disable Secure Boot."
ok "UEFI firmware present"

[ -b "$DISK" ] || die "Disk $DISK not found"
ok "Target disk present: $DISK"

if mount | grep -qE " on /mnt( |$)"; then
  die "/mnt is mounted. Run: umount -R /mnt"
fi

for c in pacman pacstrap sgdisk mkfs.fat mkfs.ext4 blkid arch-chroot findmnt; do
  need "$c"
done
ok "Required tools available"

net_ok || die "No network connectivity (HTTP/HTTPS/TCP to GitHub). Run your network bootstrap first."
ok "Network reachable"

# -------- Partition + FS --------
echo "== PARTITION AND FILESYSTEMS =="
wipefs -af "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"
EFI_PART="${DISK}1"; ROOT_PART="${DISK}2"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
ok "Filesystems created"

mkdir -p /mnt
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot
findmnt -no FSTYPE,TARGET /mnt/boot | grep -qi "vfat.*\/mnt\/boot" || die "/mnt/boot is not a FAT32 ESP"
ok "ESP mounted at /mnt/boot"

# -------- Base install --------
echo "== BASE INSTALL =="
pacstrap -K /mnt base linux linux-firmware sudo vim

# Extras de packages.x86_64 (valida nombres)
EXTRA_PKGS=()
if [ -f "$PKG_LIST" ]; then
  mapfile -t EXTRA_PKGS < <(sed 's/#.*$//' "$PKG_LIST" | tr -d '\r' | awk 'NF==1 {print $1}')
  if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then
    BAD=()
    for p in "${EXTRA_PKGS[@]}"; do
      pacman -Si "$p" >/dev/null 2>&1 || BAD+=("$p")
    done
    [ "${#BAD[@]}" -eq 0 ] || die "invalid packages in packages.x86_64: ${BAD[*]}"
    pacstrap -K /mnt "${EXTRA_PKGS[@]}"
    ok "Extra packages installed: ${EXTRA_PKGS[*]}"
  fi
fi

genfstab -U /mnt >> /mnt/etc/fstab
grep -E ' / (ext4|btrfs|xfs) ' /mnt/etc/fstab >/dev/null 2>&1 || die "fstab missing root mount"
ok "fstab generated"

ROOT_UUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"
[ -n "$ROOT_UUID" ] || die "Could not read PARTUUID for $ROOT_PART"

# -------- Configure in chroot --------
echo "== CONFIGURE SYSTEM IN CHROOT =="
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

# Microcode (best-effort)
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

# -------- UEFI fallback (Hyper-V) --------
echo "== UEFI FALLBACK =="
[ -f /mnt/boot/EFI/systemd/systemd-bootx64.efi ] || die "missing systemd-bootx64.efi in ESP"
mkdir -p /mnt/boot/EFI/BOOT
cp -f /mnt/boot/EFI/systemd/systemd-bootx64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI
[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ] || die "failed to create BOOTX64.EFI"
ok "UEFI fallback present"

# -------- Post-flight --------
echo "== POST-FLIGHT VALIDATION =="
[ -f /mnt/boot/vmlinuz-linux ]            || die "missing /boot/vmlinuz-linux"
[ -f /mnt/boot/initramfs-linux.img ]      || die "missing /boot/initramfs-linux.img"
[ -f /mnt/boot/loader/loader.conf ]       || die "missing /boot/loader/loader.conf"
[ -f /mnt/boot/loader/entries/arch.conf ] || die "missing /boot/loader/entries/arch.conf"
grep -q "root=PARTUUID=${ROOT_UUID}" /mnt/boot/loader/entries/arch.conf || die "arch.conf PARTUUID mismatch"
findmnt -no FSTYPE,TARGET /mnt/boot | grep -qi "vfat.*\/mnt\/boot" || die "ESP not mounted at /mnt/boot"
ok "All critical boot assets verified"

echo
ok "INSTALLATION PASS. Run: umount -R /mnt ; reboot (remove ISO)."
echo "Ensure Secure Boot is disabled in Hyper-V."
