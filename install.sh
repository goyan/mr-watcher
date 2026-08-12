#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

swift build -c release

APP_BUNDLE="/Applications/MRWatcher.app"
APP_DIR="$APP_BUNDLE/Contents/MacOS"

# Quitter l'app si elle tourne avant d'écraser le binaire
pkill -x MRWatcher 2>/dev/null || true
sleep 1

mkdir -p "$APP_DIR"
rm -f "$APP_DIR/MRWatcher"
cp .build/release/MRWatcher "$APP_DIR/MRWatcher"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MRWatcher</string>
  <key>CFBundleIdentifier</key><string>com.goyan.mrwatcher</string>
  <key>CFBundleName</key><string>MRWatcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# Signature ad-hoc (nécessaire pour UNUserNotificationCenter)
codesign --force --sign - "$APP_BUNDLE"

echo "✓ Installé dans $APP_BUNDLE"
echo "Lance-le avec : open $APP_BUNDLE"
