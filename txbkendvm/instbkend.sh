#!/bin/sh
set -euo pipefail

PROFILE_DIR="/mnt/shared/archinstall/txbkendvm"
CONFIG="${PROFILE_DIR}/user_configuration.json"
CREDS="${PROFILE_DIR}/user_credentials.json"

if [ ! -f "$CONFIG" ] || [ ! -f "$CREDS" ]; then
  echo "[ERROR] Faltan archivos de configuración en $PROFILE_DIR"
  echo "        Esperado: user_configuration.json y user_credentials.json"
  exit 1
fi

echo "[INFO] Ejecutando archinstall para txbkendvm..."
archinstall --config "$CONFIG" --creds "$CREDS"
