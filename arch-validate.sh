#!/usr/bin/env bash
set -euo pipefail

fail=0
note() { printf "[*] %s\n" "$*"; }
ok()   { printf "[OK] %s\n" "$*"; }
bad()  { printf "[!!] %s\n" "$*" >&2; fail=1; }

if [ -d /run/archiso ]; then
  bad "Estas en el live ISO. Usa arch-chroot /mnt antes de validar."
  exit 1
fi

note "Comprobando paquetes base"
for p in linux linux-firmware base; do
  pacman -Q "$p" >/dev/null 2>&1 && ok "Paquete $p instalado" || bad "Falta $p"
done

note "Comprobando /boot"
[ -f /boot/vmlinuz-linux ] && ok "Kernel presente" || bad "Falta kernel"
[ -f /boot/initramfs-linux.img ] && ok "initramfs presente" || bad "Falta initramfs"
[ -f /boot/loader/loader.conf ] && ok "loader.conf presente" || bad "Falta loader.conf"
[ -f /boot/loader/entries/arch.conf ] && ok "arch.conf presente" || bad "Falta arch.conf"

note "Validando arch.conf"
grep -q "root=PARTUUID=" /boot/loader/entries/arch.conf && ok "root=PARTUUID configurado" || bad "root=PARTUUID faltante"

note "systemd-boot status"
bootctl --path=/boot status >/dev/null 2>&1 && ok "systemd-boot instalado" || bad "systemd-boot no detectado"

note "fstab"
grep -E ' / (ext4|btrfs|xfs) ' /etc/fstab >/dev/null 2>&1 && ok "fstab tiene /" || bad "fstab sin entrada de /"

note "Servicios de red"
systemctl is-enabled systemd-networkd >/dev/null 2>&1 && ok "systemd-networkd habilitado" || bad "no habilitado"
systemctl is-enabled systemd-resolved >/dev/null 2>&1 && ok "systemd-resolved habilitado" || bad "no habilitado"

note "Archivo .network"
if ls /etc/systemd/network/*.network >/dev/null 2>&1; then
  ok ".network existe"
else
  bad "No hay archivos .network"
fi

note "Red"
if ping -c1 archlinux.org >/dev/null 2>&1; then
  ok "Ping a archlinux.org OK"
else
  bad "Ping fallo"
fi

note "Usuarios"
id root >/dev/null 2>&1 && ok "root existe" || bad "root no existe"
getent passwd user >/dev/null 2>&1 && ok "usuario user existe" || echo "[*] Usuario distinto"

if [ $fail -eq 0 ]; then
  echo "=== VALIDACION COMPLETA ==="
  exit 0
else
  echo "=== VALIDACION CON FALLOS ===" >&2
  exit 1
fi
