#!/usr/bin/env bash
# install_app_icon <Sources dir> <bundle Resources dir>
# Builds AppIcon.icns from the asset catalog's AppIcon set, the icon
# Info.plist names in CFBundleIconFile. Shared by the dev and release bundles
# so both show Earshot's icon.
install_app_icon() {
    local set="$1/Assets.xcassets/AppIcon.appiconset"
    local iconset
    iconset="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$iconset"
    cp "$set"/icon_*.png "$iconset/"
    iconutil -c icns "$iconset" -o "$2/AppIcon.icns"
    rm -rf "$(dirname "$iconset")"
    echo "  App icon: $2/AppIcon.icns"
}
