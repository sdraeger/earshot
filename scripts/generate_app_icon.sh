#!/usr/bin/env bash
# Renders scripts/draw_app_icon.swift at 1024 px and writes every size of
# app/Earshot/Sources/Assets.xcassets/AppIcon.appiconset from it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$ROOT/app/Earshot/Sources/Assets.xcassets/AppIcon.appiconset"
MASTER="$(mktemp -d)/icon_1024.png"
swift "$ROOT/scripts/draw_app_icon.swift" "$MASTER"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
echo "Wrote $SET"
