#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Keep the signed app on the Mac filesystem: external exFAT volumes create
# AppleDouble ._* files that break bundle signing.
APP="${TAPWALL_APP_PATH:-$HOME/Applications/TapWall.app}"
if [ -e "$APP" ]; then
  EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
  if [ "$EXISTING_ID" != "local.desktop-tumble.app" ]; then
    printf 'Refusing to overwrite unrelated app: %s\n' "$APP" >&2
    exit 1
  fi
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TapWall</string>
<key>CFBundleIdentifier</key><string>local.desktop-tumble.app</string>
<key>CFBundleName</key><string>TapWall</string>
<key>CFBundleDisplayName</key><string>TapWall</string>
<key>CFBundleIconFile</key><string>TapWall</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>读取真实桌面项目的名称和图标，用于互动展示；不会修改或移动文件。</string>
</dict></plist>
PLIST
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -O -framework AppKit -framework SceneKit -framework SwiftUI -framework AVFoundation Sources/*.swift -o "$APP/Contents/MacOS/TapWall"
cp Assets/TapWall.icns Assets/TapWall.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
