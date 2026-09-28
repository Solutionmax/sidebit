#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift
iconutil -c icns .build/AppIcon.iconset -o Sources/Snipkin/Resources/AppIcon.icns
swift build -c release
build_dir="$(swift build -c release --show-bin-path)"
app="dist/Sidebit.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$build_dir/Snipkin" "$app/Contents/MacOS/Sidebit"
cp Info.plist "$app/Contents/Info.plist"
ditto "$build_dir/Snipkin_Snipkin.bundle" "$app/Contents/Resources/Snipkin_Snipkin.bundle"
if [ -f Sources/Snipkin/Resources/AppIcon.icns ]; then
    cp Sources/Snipkin/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
# A stable identity keeps macOS privacy grants (Accessibility) across updates; ad-hoc pins them to one build.
if [ -n "${SIDEBIT_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$SIDEBIT_SIGN_IDENTITY" "$app"
else
    echo "warning: SIDEBIT_SIGN_IDENTITY not set, signing ad-hoc (Accessibility grant resets every build)" >&2
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)"
grep -q "current = \"$version\"" Sources/SnipkinCore/Usage.swift || { echo "Version mismatch: Info.plist $version vs SidebitVersion" >&2; exit 1; }
rm -f "dist/Sidebit-$version-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Sidebit-$version-arm64.zip"
if [ -n "${SIDEBIT_UPDATE_KEY:-}" ]; then swift scripts/update-sign.swift sign "dist/Sidebit-$version-arm64.zip"; fi
echo "Built: $app"
