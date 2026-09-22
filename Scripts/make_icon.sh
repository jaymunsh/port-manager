#!/bin/bash
# Generates Resources/AppIcon.icns via Scripts/render_icon.swift + iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swift Scripts/render_icon.swift "$TMP/icon_1024.png"

mkdir -p "$TMP/AppIcon.iconset"
for spec in "16x16:16" "16x16@2x:32" "32x32:32" "32x32@2x:64" "128x128:128" \
            "128x128@2x:256" "256x256:256" "256x256@2x:512" "512x512:512" "512x512@2x:1024"; do
    name="${spec%%:*}"
    px="${spec##*:}"
    sips -z "$px" "$px" "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${name}.png" >/dev/null
done

iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"
