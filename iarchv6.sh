#!/usr/bin/env bash
set -Eeuo pipefail

# iarch-autopilot-log.sh — Arch para Hyper-V Gen2 (UEFI, Secure Boot OFF)
# Pre-flight + instalación + validación + logs JSON/TXT y copia al host (SMB).

# ===== Opcional: overrides por variable de entorno =====
DISK="${DISK:-auto}"                 # auto|/dev/sda|/dev/vda|/dev/nvme0n1
HOSTNAME="${HOSTNAME:-archvm}"
USERNAME="${USERNAME:-user}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
USER_PASSWORD="${USER_PASSWORD:-user}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-la-latin1}"
TIMEZONE="${TIMEZONE:-America/Monterrey}"

# SMB para copiar logs al host (puedes override con env)
SMB_SHARE="${SMB_SHARE:-txVMsharedvolume}"
SMB_USER="${SMB_USER:-smbtxVM}"
SMB_PASS="${SMB_PASS:-aalH#@wcVJs@lWyJ}"
SMB_MOUNT="/mnt/winshare"   # punto de montaje temporal en el ISO

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_LIST="$SCRIPT_DIR/packages.x86_64"

# ===== Logs =====
TS="$(date +%Y%m%d-%H%M%S)"
LOGTXT="iarch-${TS}.log"
LOGJSON="install-log-${TS}.json"
exec > >(tee -a "$LOGTXT") 2>&1

ok(){ printf "[OK] %s\n" "$*"; }
_fail_reason=""
die(){ _fail_reason="$*"; echo "[!!] $_fail_reason" >&2; write_json "FAIL"; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ===== Utilidades red/mirada =====
tcp_443(){ timeout 6 bash -c ">/dev/tcp/$1/443" >/dev/null 2>&1; }
http_ok_if(){
  local ifc="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSIL --interface "$ifc" --max-time 8 https://github.com/ >/dev/null 2>&1 && return 0
    curl -fsSIL --interface "$ifc" --max-time 8 https://raw.githubusercontent.com/ >/dev/null 2>&1 && return 0
    curl -fsSIL --interface "$ifc" --max-time 8 https://geo.mirror.pkgbuild.com/ >/dev/null 2>&1 && return 0
  fi
  tcp_443 1.1.1.1 && return 0
  return 1
}
in_109964(){ [[ "$1" =~ ^10\.99\.64\.[0-9]+$ ]]; }

# ===== Recolectores para JSON =====
KERNEL=""; VIRT=""; UEFI="false"
DISK_LIST=""; CHOSEN_DISK=""
JSON_NICS=""
BEST_IF=""; BEST_KIND=""; BEST_MODE=""; BEST_ADDR=""; BEST_GW=""
VP_IF=""; VP_ADDR=""
EFI_PART=""; ROOT_PART=""; ROOT_UUID=""
MIRRORS=('https://geo.mirror.pkgbuild.com/$repo/os/$arch' 'https://mirror.rackspace.com/archlinux/$repo/os/$arch')
VALID=()

append_nic_json(){
  local ifc="$1" ip="$2" gw="$3" kind="$4" inet="$5"
  local comma=""
  [[ -n "$JSON_NICS" ]] && comma=","
  JSON_NICS="${JSON_NICS}${comma}{\"if\":\"$ifc\",\"ip\":\"${ip:-}\",\"gw\":\"${gw:-}\",\"kind\":\"$kind\",\"has_inet\":$inet}"
}

write_json(){
  local status="$1"
  # Determinar host SMB por heurística (para dejar constancia en JSON)
  local smb_host="${SMB_HOST:-}"
  if [[ -z "$smb_host" ]]; then
    if [[ "$BEST_KIND" = "default" && -n "$BEST_GW" ]]; then smb_host="$BEST_GW"
    elif [[ "$BEST_KIND" = "vprivado" && -n "$BEST_GW" ]]; then smb_host="$BEST_GW"
    else smb_host=""
    fi
  fi
  cat > "$LOGJSON" <<JSON
{
  "timestamp":"$(date -Is)",
  "status":"$status",
  "fail_reason":"${_fail_reason//\"/\\\"}",
  "env": {
    "kernel":"$KERNEL",
    "virt":"$VIRT",
    "uefi":$([ "$UEFI" = "true" ] && echo true || echo false)
  },
  "disks": {
    "list":"${DISK_LIST//\"/\\\"}",
    "chosen":"$CHOSEN_DISK"
  },
  "network": {
    "nics":[ $JSON_NICS ],
    "inet_choice":{"if":"$BEST_IF","kind":"$BEST_KIND","mode":"$BEST_MODE","addr":"$BEST_ADDR","gw":"$BEST_GW"},
    "vprivado_extra":{"if":"$VP_IF","addr":"$VP_ADDR"},
    "smb": {"host":"$smb_host","share":"$SMB_SHARE","user":"$SMB_USER"}
  },
  "mirrors": [${MIRRORS[@]/#/\"}], 
  "partitions": {"efi":"$EFI_PART","root":"$ROOT_PART","root_partuuid":"$ROOT_UUID"},
  "validations": [${VALID[*]:-}],
  "config": {
    "hostname":"$HOSTNAME",
    "username":"$USERNAME",
    "locale":"$LOCALE",
    "timezone":"$TIMEZONE",
    "keymap":"$KEYMAP"
  },
  "artifacts": {
    "text_log":"$LOGTXT",
    "json_log":"$LOGJSON",
    "saved_to": {
      "target": "/var/log/iarch/",
      "smb_copy_attempted": ${SMB_TRIED:-false},
      "smb_copy_ok": ${SMB_OK:-false}
    }
  }
}
JSON
}

# ===== Limpieza segura =====
cleanup(){
  mountpoint -q "$SMB_MOUNT" && umount "$SMB_MOUNT" || true
  mountpoint -q /mnt && umount -R /mnt || true
}
trap cleanup EXIT

# ===== PRE-FLIGHT =====
echo "=== PRE-FLIGHT $(date -Is) ==="
need pacman; need pacstrap; need sgdisk; need mkfs.fat; need mkfs.ext4; need blkid; need arch-chroot; need findmnt; need lsblk; need awk; need sed; need tee; need curl

KERNEL="$(uname -r || true)"
VIRT="$(systemd-detect-virt || true)"
if [ -d /sys/firmware/efi ]; then UEFI="true"; else die "UEFI requerido (Gen2)."; fi

DISK_LIST="$(lsblk -dno NAME,TYPE,SIZE,MODEL || true; echo; lsblk -f || true)"
if [ "$DISK" = "auto" ]; then
  d=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE '^(sr|loop|zram)' | head -1)
  CHOSEN_DISK="/dev/$d"
else
  CHOSEN_DISK="$DISK"
fi
[ -b "$CHOSEN_DISK" ] || die "No existe $CHOSEN_DISK"
ok "Disco: $CHOSEN_DISK"

mount | grep -qE " on /mnt( |$)" && die "/mnt está montado; ejecuta: umount -R /mnt"

# NICs y elección con Internet
mapfile -t IFACES < <(ip -o -4 addr show up | awk '$2!="lo"{print $2}' | sort -u)
[ "${#IFACES[@]}" -gt 0 ] || die "No hay NICs IPv4 levantadas."
for IF in "${IFACES[@]}"; do
  ADDR_CIDR="$(ip -o -4 addr show dev "$IF" | awk '{print $4}' | head -1)"
  IP="${ADDR_CIDR%/*}"
  GW="$(ip -4 route show default 0.0.0.0/0 dev "$IF" 2>/dev/null | awk '{print $3; exit}')"
  KIND="default"; MODE="dhcp"
  if in_109964 "$IP"; then KIND="vprivado"; MODE="static"; [[ -z "$GW" ]] && GW="10.99.64.1"; fi
  if http_ok_if "$IF"; then
    HAS_INET=true
    if [[ -z "$BEST_IF" || ( "$BEST_KIND" != "default" && "$KIND" = "default" ) ]]; then
      BEST_IF="$IF"; BEST_KIND="$KIND"; BEST_MODE="$MODE"; BEST_ADDR="$ADDR_CIDR"; BEST_GW="$GW"
    fi
  else
    HAS_INET=false
  fi
  append_nic_json "$IF" "$IP" "$GW" "$KIND" "$HAS_INET"
  [[ "$KIND" = "vprivado" ]] && { VP_IF="$IF"; VP_ADDR="$ADDR_CIDR"; }
done
[[ -n "$BEST_IF" ]] || die "Ningún adaptador ofrece Internet (HTTP/443). Conecta Default Switch o abre salida."
ok "INET por $BEST_IF ($BEST_KIND)"

# Mirrors (fijos y confiables)
cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF
ok "Mirrorlist definida"

# ===== PARTICIONES + FS =====
wipefs -af "$CHOSEN_DISK"
sgdisk -Z "$CHOSEN_DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$CHOSEN_DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$CHOSEN_DISK"
EFI_PART="${CHOSEN_DISK}1"; ROOT_PART="${CHOSEN_DISK}2"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
mkdir -p /mnt && mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot && mount "$EFI_PART" /mnt/boot
findmnt -no FSTYPE,TARGET /mnt/boot | grep -qi 'vfat.*/mnt/boot' || die "/mnt/boot no es la ESP (vfat)."
ok "ESP OK"
ROOT_UUID="$(blkid -s PARTUUID -o value "$ROOT_PART")"; [ -n "$ROOT_UUID" ] || die "No pude leer PARTUUID"

# ===== BASE + EXTRAS =====
pacstrap -K /mnt base linux linux-firmware sudo vim
if [ -f "$PKG_LIST" ]; then
  mapfile -t EXTRA < <(sed 's/#.*$//' "$PKG_LIST" | tr -d '\r' | awk 'NF==1{print $1}')
  if [ "${#EXTRA[@]}" -gt 0 ]; then
    VALID_PKGS=(); INVALID_PKGS=()
    for p in "${EXTRA[@]}"; do pacman -Si "$p" >/dev/null 2>&1 && VALID_PKGS+=("$p") || INVALID_PKGS+=("$p"); done
    [ "${#VALID_PKGS[@]}" -gt 0 ] && pacstrap -K /mnt "${VALID_PKGS[@]}"
    [ "${#INVALID_PKGS[@]}" -gt 0 ] && echo "[*] Paquetes inválidos (omitidos): ${INVALID_PKGS[*]}"
  fi
fi
ok "Base (y extras válidos) instalados"

genfstab -U /mnt >> /mnt/etc/fstab
awk '$1 !~ /^#/ && $2=="/"{f=1} END{exit f?0:1}' /mnt/etc/fstab || {
  : > /mnt/etc/fstab; genfstab -U /mnt >> /mnt/etc/fstab
  awk '$1 !~ /^#/ && $2=="/"{f=1} END{exit f?0:1}' /mnt/etc/fstab || die "fstab sin raíz"
}
VALID+=('"fstab_root":true')
ok "fstab OK"

# ===== RED DEL SISTEMA INSTALADO =====
mkdir -p /mnt/etc/systemd/network
if [ "$BEST_MODE" = "dhcp" ]; then
  cat >/mnt/etc/systemd/network/10-inet.network <<EOF
[Match]
Name=e*

[Network]
DHCP=ipv4
DNS=1.1.1.1

[DHCPv4]
RouteMetric=100
EOF
else
  cat >/mnt/etc/systemd/network/10-inet.network <<EOF
[Match]
Name=e*

[Network]
Address=$BEST_ADDR
Gateway=$BEST_GW
DNS=1.1.1.1
IPv6AcceptRA=no
EOF
fi
if [[ -n "$VP_IF" && "$VP_IF" != "$BEST_IF" ]]; then
  cat >/mnt/etc/systemd/network/20-vprivado.network <<EOF
[Match]
Name=e*

[Network]
Address=${VP_ADDR:-10.99.64.10/24}
DNS=1.1.1.1
IPv6AcceptRA=no
EOF
fi

# ===== CONFIG SISTEMA (chroot) =====
export LOCALE KEYMAP TIMEZONE HOSTNAME USERNAME ROOT_PASSWORD USER_PASSWORD ROOT_UUID
arch-chroot /mnt /bin/bash -eu <<'CH'
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
systemctl enable systemd-networkd systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
echo "root:${ROOT_PASSWORD}" | chpasswd
id "${USERNAME}" >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
grep -qi GenuineIntel /proc/cpuinfo && pacman -Sy --noconfirm intel-ucode || true
grep -qi AuthenticAMD /proc/cpuinfo && pacman -Sy --noconfirm amd-ucode   || true
mkinitcpio -P
bootctl --path=/boot install
UCODE_LINE=""
[ -f /boot/intel-ucode.img ] && UCODE_LINE="initrd  /intel-ucode.img"
[ -f /boot/amd-ucode.img ]   && UCODE_LINE="initrd  /amd-ucode.img"
mkdir -p /boot/loader/entries
cat >/boot/loader/entries/arch.conf <<EOT
title   Arch Linux
linux   /vmlinuz-linux
$UCODE_LINE
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
# Guardar logs también dentro del sistema instalado
mkdir -p /var/log/iarch
CH

# Fallback UEFI obligatorio
install -D /mnt/boot/EFI/systemd/systemd-bootx64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI
[ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ] || die "No se creó BOOTX64.EFI"
VALID+=('"uefi_fallback":true')

# Validaciones finales
[ -f /mnt/boot/vmlinuz-linux ]       || die "Falta vmlinuz-linux"
[ -f /mnt/boot/initramfs-linux.img ] || die "Falta initramfs-linux.img"
[ -f /mnt/boot/loader/loader.conf ]  || die "Falta loader.conf"
[ -f /mnt/boot/loader/entries/arch.conf ] || die "Falta arch.conf"
grep -q "root=PARTUUID=${ROOT_UUID}" /mnt/boot/loader/entries/arch.conf || die "PARTUUID incorrecto en arch.conf"
findmnt -no FSTYPE,TARGET /mnt/boot | grep -qi 'vfat.*/mnt/boot' || die "ESP desmontada/incorrecta"
VALID+=('"kernel_initramfs":true,"partuuid_matches":true,"esp_vfat":true')

# Escribir JSON ahora que tenemos todo:
write_json "PASS"

# Copias locales de logs en el sistema instalado
cp -f "$LOGTXT" "$LOGJSON" /mnt/var/log/iarch/ || true

# ===== Copiar logs al host por SMB (si es posible) =====
SMB_TRIED=true; SMB_OK=false
# Heurística: host = gateway de la interfaz INET elegida; si vPrivado sin gateway, asumir 10.99.64.1
if [[ -z "${SMB_HOST:-}" ]]; then
  if [[ "$BEST_KIND" = "default" && -n "$BEST_GW" ]]; then SMB_HOST="$BEST_GW"
  elif [[ -n "$BEST_GW" ]]; then SMB_HOST="$BEST_GW"
  else SMB_HOST="10.99.64.1"
  fi
fi
echo "[*] Intentando SMB hacia //$SMB_HOST/$SMB_SHARE ..."
pacman -Sy --needed --noconfirm cifs-utils smbclient >/dev/null 2>&1 || true
if command -v mount.cifs >/dev/null 2>&1; then
  mkdir -p "$SMB_MOUNT"
  # Crear credenciales temporales
  CREDS="/root/.cifs.$$"
  printf "username=%s\npassword=%s\n" "$SMB_USER" "$SMB_PASS" > "$CREDS"
  chmod 600 "$CREDS"
  if mount -t cifs "//$SMB_HOST/$SMB_SHARE" "$SMB_MOUNT" -o "credentials=$CREDS,iocharset=utf8,vers=3.0,sec=ntlmssp,nofail" 2>/dev/null; then
    cp -f "$LOGTXT" "$LOGJSON" "$SMB_MOUNT/" && { SMB_OK=true; echo "[OK] Logs copiados al host."; }
    umount "$SMB_MOUNT" || true
  else
    echo "[*] No pude montar SMB en //$SMB_HOST/$SMB_SHARE (credenciales o firewall?)."
  fi
  rm -f "$CREDS"
else
  echo "[*] cifs-utils no disponible; omito copia SMB."
fi

# Re-escribir JSON con flags de copia actualizados
write_json "PASS"

echo
ok "INSTALLATION PASS — listo para reiniciar."
echo "[*] Logs locales: $LOGTXT  |  $LOGJSON"
echo "[*] Copia dentro del sistema: /var/log/iarch/"
echo "[*] Si configuraste el host con Prepare-Host-HyperV.ps1, encontrarás los logs en el share."
echo "[*] Desmontando /mnt y reiniciando… quita el ISO."
umount -R /mnt || true
reboot -f
