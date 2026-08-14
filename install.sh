#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

swift build -c release

APP_BUNDLE="/Applications/MRWatcher.app"
APP_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
ICON_SOURCE="Assets/AppIcon.png"

# Quitter l'app si elle tourne avant d'écraser le binaire
pkill -x MRWatcher 2>/dev/null || true
sleep 1

mkdir -p "$APP_DIR" "$RESOURCES_DIR"
rm -f "$APP_DIR/MRWatcher"
cp .build/release/MRWatcher "$APP_DIR/MRWatcher"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Icône introuvable : $ICON_SOURCE" >&2
  exit 1
fi

ICONSET_DIR="$(mktemp -d)/MRWatcher.iconset"
mkdir -p "$ICONSET_DIR"
trap 'rm -rf "${ICONSET_DIR%/MRWatcher.iconset}"' EXIT

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  doubled_size=$((size * 2))
  sips -z "$doubled_size" "$doubled_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/MRWatcher.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MRWatcher</string>
  <key>CFBundleIdentifier</key><string>com.goyan.mrwatcher</string>
  <key>CFBundleIconFile</key><string>MRWatcher</string>
  <key>CFBundleName</key><string>MRWatcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# Signature ad-hoc (nécessaire pour UNUserNotificationCenter)
codesign --force --sign - "$APP_BUNDLE"

echo "✓ Installé dans $APP_BUNDLE"
echo "Lance-le avec : open $APP_BUNDLE"
