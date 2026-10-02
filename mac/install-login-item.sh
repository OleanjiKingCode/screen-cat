#!/bin/bash
# Adds (or removes) a LaunchAgent so Screen Cat starts when you log in.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="local.screencat"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$(pwd)/ScreenCat.app/Contents/MacOS/ScreenCat"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "removed login item"
  exit 0
fi

if [ ! -x "$BIN" ]; then
  echo "build it first: ./build.sh" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Screen Cat will start at login. Remove with: ./install-login-item.sh --uninstall"
