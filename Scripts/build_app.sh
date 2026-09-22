#!/bin/bash
# Builds the SwiftPM binary and assembles PortManager.app.
# Usage: ./Scripts/build_app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="PortManager.app"
BIN=".build/${CONFIG}/PortManager"

echo "▶ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

if [ ! -f "$BIN" ]; then
    echo "✗ binary not found at $BIN" >&2
    exit 1
fi

echo "▶ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PortManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so the bundle keeps a stable identity (notifications, settings).
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ $APP ready"
