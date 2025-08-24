#!/usr/bin/env bash
set -Eeuo pipefail

# iarchv8.sh — Arch Linux base para Hyper-V Gen2 (UEFI)
# - Particiona: ESP + ROOT
# - Instala base + extras (packages.x86_64 junto al script, si existe)
# - Configura red con systemd-networkd (DHCP)
# - Instala systemd-boot y crea fallback EFI/BOOT/BOOTX64.EFI
# - Evita fallar si /etc/resolv.conf ya apunta al stub

# ===== Parámetros (puedes exportarlos antes) =====
DISK="${DISK:-auto}"           # auto | /dev/sda | /dev/vda | /dev/nvme0n1
HOSTNAME="${HOSTNAME:-archvm}"
USERNAME="${USERNAME:-user}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
USER_PASSWORD="${USER_PASSWORD:-user}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-la-latin1}"
TIMEZONE="${TIMEZONE:-America/Monterrey}"
NO_REBOOT="${NO_REBOOT:-}"     # si no vacío, no reinicia al final

# ===== Utilidades =====
die(){ echo "[!!] $*" >&2; exit 1; }
ok(){  echo "[OK] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || die "falta comando: $1"; }

# ===== Pre-flight =====
need pacman; need pacstrap; need sgdisk; need mkfs.fat; need mkfs.ext4; need blkid; need arch-chroot
[ -d /sys/firmware/efi ] || die "Esta VM NO está en UEFI (Hyper-V Gen2)."

# Mirrors simples/fiables
cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF

# Disco
if [ "$DISK" = "auto" ]; then
  d=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE '^(sr|loop|zram)' | head -1)
  DISK="/dev/$d"
fi
[ -b "$DISK" ] || die "No existe $DISK"
mountpoint -q /mnt && die "/mnt ya está montado (umount -R /mnt)"
ok "Usando disco $DISK"

# ===== Particiones y FS =====
wipefs -af "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"
EFI_PART="${DISK}1"; ROOT_PART="${DISK}2"

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

mkdir -p /mnt
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART"  /mnt/boot
ok "ESP y ROOT montadas"

# ===== Base y extras =====
pacstrap -K /mnt base linux linux-firmware sudo vim

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"
if [ -f "$PKG_LIST" ]; then
  mapfile -t EXTRA < <(sed 's/#.*$//' "$PKG_LIST" | tr -d '\r' | awk 'NF==1{print $1}')
  if [ "${#EXTRA[@]}" -gt 0 ]; then
    GOOD=()
    for p in "${EXTRA[@]}"; do pacman -Si "$p" >/dev/null 2>&1 && GOOD+=("$p") || echo "[*] Ignoro paquete inválido: $p"; done
    [ "${#GOOD[@]}" -gt 0 ] && pacstrap -K /mnt "${GOOD[@]}"
  fi
fi
ok "Base (y extras válidos) instalada"

# fstab
genfstab -U /mnt >> /mnt/etc/fstab
grep -qE '^[^#]+\s+/\s+' /mnt/etc/fstab || die "fstab no contiene raíz montada"

# PARTUUID raíz
ROOT_UUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"
[ -n "$ROOT_UUID" ] || die "No pude leer PARTUUID de $ROOT_PART"

# ===== Config dentro del sistema =====
export LOCALE KEYMAP TIMEZONE HOSTNAME USERNAME ROOT_PASSWORD USER_PASSWORD ROOT_UUID
arch-chroot /mnt /bin/bash -eu <<'CH'
set -Eeuo pipefail

# Locales/teclado/tiempo
echo "${LOCALE} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Hostname/hosts
echo "${HOSTNAME}" > /etc/hostname
cat >/etc/hosts <<EOT
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOT

# Red: systemd-networkd DHCP para e* + resolved
mkdir -p /etc/systemd/network
cat >/etc/systemd/network/10-dhcp.network <<'EOT'
[Match]
Name=e*

[Network]
DHCP=ipv4
DNS=1.1.1.1

[DHCPv4]
RouteMetric=100
EOT
systemctl enable systemd-networkd systemd-resolved

# resolv.conf tolerante (no fallar si ya apunta al stub)
tgt="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
if [ "$tgt" != "/run/systemd/resolve/stub-resolv.conf" ]; then
  rm -f /etc/resolv.conf
  ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# Usuarios/sudo
echo "root:${ROOT_PASSWORD}" | chpasswd
id "${USERNAME}" >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# initramfs
mkinitcpio -P

# microcode (opcional, mejor si hay red)
grep -qi GenuineIntel /proc/cpuinfo && pacman -Sy --noconfirm intel-ucode || true
grep -qi AuthenticAMD /proc/cpuinfo && pacman -Sy --noconfirm amd-ucode   || true

# systemd-boot + entradas
bootctl --path=/boot install
UC=""
[ -f /boot/intel-ucode.img ] && UC="initrd  /intel-ucode.img"
[ -f /boot/amd-ucode.img ]   && UC="initrd  /amd-ucode.img"

mkdir -p /boot/loader/entries
cat >/boot/loader/entries/arch.conf <<EOT
title   Arch Linux
linux   /vmlinuz-linux
$UC
initrd  /initramfs-linux.img
options root=PARTUUID=${ROOT_UUID} rw
EOT

cat >/boot/loader/loader.conf <<'EOT'
default arch
timeout 3
editor no
EOT

# Fallback UEFI obligatorio para Hyper-V Gen2
install -D /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
CH

# ===== Validaciones =====
[ -f /mnt/boot/vmlinuz-linux ]                    || die "Falta /boot/vmlinuz-linux"
[ -f /mnt/boot/initramfs-linux.img ]              || die "Falta /boot/initramfs-linux.img"
[ -f /mnt/boot/loader/entries/arch.conf ]         || die "Falta loader entry"
grep -q "root=PARTUUID=${ROOT_UUID}" /mnt/boot/loader/entries/arch.conf || die "PARTUUID no coincide en arch.conf"
[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]             || die "Falta BOOTX64.EFI (fallback)"

ok "Instalación COMPLETADA y booteable."

# ===== Salida =====
umount -R /mnt || true
if [ -z "$NO_REBOOT" ]; then
  echo "[*] Reiniciando… (retira el ISO)"
  reboot -f
else
  echo "[*] NO_REBOOT=1 — puedes reiniciar cuando quieras."
fi
