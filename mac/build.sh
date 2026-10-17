#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="ScreenCat.app"
VERSION="${VERSION:-1.1.0}"
BIN="$APP/Contents/MacOS/ScreenCat"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${UNIVERSAL:-0}" = "1" ]; then
  # One binary for Apple silicon and Intel Macs, for releases.
  TMP="$(mktemp -d)"
  for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos12" -o "$TMP/ScreenCat-$arch" Sources/*.swift 2>&1 | grep -v "^$" || true
  done
  lipo -create -output "$BIN" "$TMP/ScreenCat-arm64" "$TMP/ScreenCat-x86_64" 2>/dev/null || true
  rm -rf "$TMP"
else
  swiftc -O -o "$BIN" Sources/*.swift 2>&1 | grep -v "^$" || true
fi
if [ ! -x "$BIN" ]; then
  echo "build failed" >&2
  exit 1
fi

cp Assets/Cat_Sprite_Sheet.png Assets/Cat_Shadow.png Assets/Cat_Ball.png Assets/CREDIT.txt "$APP/Contents/Resources/"
# The dog and the app icon, when they are there.
for f in Assets/Dog_Sprite_Sheet.png Assets/Dog_Ball.png Assets/AppIcon.icns; do
  [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ScreenCat</string>
  <key>CFBundleDisplayName</key><string>Screen Cat</string>
  <key>CFBundleIdentifier</key><string>local.screencat</string>
  <key>CFBundleExecutable</key><string>ScreenCat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
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
