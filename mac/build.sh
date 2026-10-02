#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="ScreenCat.app"
BIN="$APP/Contents/MacOS/ScreenCat"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$BIN" Sources/*.swift 2>&1 | grep -v "^$" || true
if [ ! -x "$BIN" ]; then
  echo "build failed" >&2
  exit 1
fi

cp Assets/Cat_Sprite_Sheet.png Assets/Cat_Shadow.png Assets/Cat_Ball.png Assets/CREDIT.txt "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ScreenCat</string>
  <key>CFBundleDisplayName</key><string>Screen Cat</string>
  <key>CFBundleIdentifier</key><string>local.screencat</string>
  <key>CFBundleExecutable</key><string>ScreenCat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Screen Cat writes whether Bluetooth is on or off in its local activity log.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"
echo "built $(pwd)/$APP"
