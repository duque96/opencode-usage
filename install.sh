#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

./build.sh

DEST="$HOME/Applications/OpenCodeUsage.app"
PLIST="$HOME/Library/LaunchAgents/es.duque.opencodeusage.plist"
UID_NUM="$(id -u)"

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "dist/OpenCodeUsage.app" "$DEST"

if [ -f "$PLIST" ]; then
  launchctl bootout "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$PLIST"
  echo "LaunchAgent recargado."
else
  open "$DEST"
  echo "Ejecutando desde $DEST (sin LaunchAgent)."
fi

echo "Instalado en $DEST"
