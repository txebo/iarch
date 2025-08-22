#!/usr/bin/env bash
# runs.sh — envoltorio para ejecutar scripts y capturar logs completos
# Uso: ./runs.sh <script> [args...]
# Crea: <script>-<YYYYmmdd-HHMMSS>.txt con stdout+stderr
# Copia el log a $SAMBA_TARGET o /mnt/winshare si existe y es escribible.

set -u

usage() {
  echo "Uso: $0 <script> [args...]"
  exit 2
}

# --- Validaciones básicas ---
[ $# -ge 1 ] || usage
TARGET="$1"; shift || true

# Si pasaron ruta relativa, respétala; si solo nombre, anteponer ./ si existe en cwd
if [[ ! -e "$TARGET" && -e "./$TARGET" ]]; then
  TARGET="./$TARGET"
fi

if [[ ! -e "$TARGET" ]]; then
  echo "[!!] No existe el script: $TARGET"
  exit 2
fi

# Hacer ejecutable si no lo es (mejor esfuerzo)
if [[ ! -x "$TARGET" ]]; then
  chmod +x "$TARGET" 2>/dev/null || true
fi

BASE="$(basename -- "$TARGET")"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="${BASE%.*}-${TS}.txt"

# --- Encabezado del log ---
{
  echo "=== RUN START: $(date -Is) ==="
  echo "Host: $(hostname)  Kernel: $(uname -r)"
  echo "User: $(id -un) (UID=$(id -u))  PWD: $(pwd)"
  echo "Script: $TARGET"
  echo "Args: ${*:-<sin argumentos>}"
  if command -v sha256sum >/dev/null 2>&1; then
    echo "SHA256: $(sha256sum "$TARGET" | awk '{print $1}')"
  fi
  echo "--------------------------------"
} > "$LOG"

# --- Ejecución con captura completa (stdout+stderr) ---
set -o pipefail
# stdbuf asegura salida line-buffered para ver y registrar en tiempo real si lo deseas con 'tee'
stdbuf -oL -eL bash "$TARGET" "$@" 2>&1 | tee -a "$LOG"
EC=${PIPESTATUS[0]}

{
  echo "--------------------------------"
  echo "Exit code: $EC"
  echo "=== RUN END: $(date -Is) ==="
} | tee -a "$LOG" >/dev/null

# --- Copia opcional al share SMB si está disponible ---
COPIED=0
copy_to() {
  local dst="$1"
  if [[ -d "$dst" && -w "$dst" ]]; then
    cp -f -- "$LOG" "$dst/" && {
      echo "[copied] $LOG -> $dst/" | tee -a "$LOG" >/dev/null
      COPIED=1
    }
  fi
}

# Prioridad: SAMBA_TARGET (si está definida), luego /mnt/winshare
if [[ -n "${SAMBA_TARGET:-}" ]]; then
  copy_to "$SAMBA_TARGET"
fi
copy_to "/mnt/winshare"

# Mensaje final en consola
if [[ $COPIED -eq 1 ]]; then
  echo "[OK] Log local: ./$LOG  (copiado también al share disponible)"
else
  echo "[OK] Log local: ./$LOG"
fi

exit "$EC"
