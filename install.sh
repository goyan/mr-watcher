#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$REPO_ROOT"

VERSION_FILE="$REPO_ROOT/VERSION"
DEFAULT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
DEFAULT_VERSION="${DEFAULT_VERSION:-0.0.0}"
MRWATCHER_VERSION="${MRWATCHER_VERSION:-$DEFAULT_VERSION}"
APP_BUNDLE="${MRWATCHER_APP_BUNDLE:-/Applications/MRWatcher.app}"
KILL_RUNNING_APP="${MRWATCHER_KILL_RUNNING_APP:-1}"
DIST_APP_BUNDLE="$REPO_ROOT/dist/MRWatcher.app"
SPARKLE_ARTIFACT_ROOT="$REPO_ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK_SOURCE="$SPARKLE_ARTIFACT_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FRAMEWORK_INFO="$SPARKLE_FRAMEWORK_SOURCE/Versions/B/Resources/Info.plist"

fail() {
  echo "$*" >&2
  exit 1
}

assert_no_symlink_components() {
  local path="$1"
  local current=""
  local component
  local parts=()

  IFS='/' read -r -a parts <<< "$path"
  for component in "${parts[@]}"; do
    [[ -z "$component" ]] && continue
    current="$current/$component"
    [[ ! -L "$current" ]] || fail "Chemin refusé : composant symbolique détecté ($current)."
  done
}

validate_app_bundle() {
  [[ "$APP_BUNDLE" == /* ]] || fail "MRWATCHER_APP_BUNDLE doit être un chemin absolu autorisé."
  case "$APP_BUNDLE" in
    /Applications/MRWatcher.app|"$DIST_APP_BUNDLE") ;;
    *) fail "MRWATCHER_APP_BUNDLE doit être /Applications/MRWatcher.app ou $DIST_APP_BUNDLE." ;;
  esac
  assert_no_symlink_components "$APP_BUNDLE"
}

validate_sparkle_framework() {
  [[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]] || fail "L'artefact Sparkle 2.9 est introuvable : $SPARKLE_FRAMEWORK_SOURCE"
  [[ -f "$SPARKLE_FRAMEWORK_INFO" ]] || fail "Info.plist Sparkle introuvable : $SPARKLE_FRAMEWORK_INFO"

  local sparkle_version
  sparkle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SPARKLE_FRAMEWORK_INFO")"
  [[ "$sparkle_version" == 2.9.* ]] || fail "Version Sparkle inattendue : $sparkle_version (2.9.x requise)."
}

if [[ ! "$MRWATCHER_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "MRWATCHER_VERSION doit être une version numérique MAJEUR.MINEUR.CORRECTIF." >&2
  exit 64
fi

validate_app_bundle
swift build -c release
validate_sparkle_framework

APP_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
ICON_SOURCE="Assets/AppIcon.png"

# Quitter l'app si elle tourne avant d'écraser le binaire
if [[ "$KILL_RUNNING_APP" == "1" ]]; then
  pkill -x MRWatcher 2>/dev/null || true
  sleep 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp .build/release/MRWatcher "$APP_DIR/MRWatcher"
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
cp RELEASE_NOTES.md "$RESOURCES_DIR/RELEASE_NOTES.md"

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

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MRWatcher</string>
  <key>CFBundleIdentifier</key><string>com.goyan.mrwatcher</string>
  <key>CFBundleIconFile</key><string>MRWatcher</string>
  <key>CFBundleName</key><string>MRWatcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>${MRWATCHER_VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${MRWATCHER_VERSION}</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/goyan/mr-watcher/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>WVZl0Cunt1pb4SuDL0WFNiFaYLTcU7M5rwYJA547rGA=</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>3600</integer>
</dict></plist>
PLIST

if ! otool -l "$APP_DIR/MRWatcher" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/MRWatcher"
fi

# Signature ad-hoc du bundle et des composants Sparkle embarqués.
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✓ Installé dans $APP_BUNDLE"
echo "Lance-le avec : open $APP_BUNDLE"
