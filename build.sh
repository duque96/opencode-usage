#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="OpenCodeUsage"
APP_DIR="dist/${APP_NAME}.app"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

echo "Compilando ${APP_NAME}…"
swiftc -O -swift-version 5 -framework Cocoa -framework Security \
  -o "${APP_DIR}/Contents/MacOS/${APP_NAME}" \
  "${APP_NAME}.swift"

cp Info.plist "${APP_DIR}/Contents/Info.plist"

# Firma ad-hoc: suficiente para ejecutarlo localmente.
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "Construido: ${APP_DIR}"
echo "Para ejecutarlo: open \"${APP_DIR}\""
