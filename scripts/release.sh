#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

usage() {
  echo "Usage: $0 <version-semver>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
VERSION="$1"
SEMVER_NUMBER='(0|[1-9][0-9]*)'
SEMVER_REGEX="^${SEMVER_NUMBER}\.${SEMVER_NUMBER}\.${SEMVER_NUMBER}$"

if [[ ! "$VERSION" =~ $SEMVER_REGEX ]]; then
  echo "Version invalide : utilisez MAJEUR.MINEUR.CORRECTIF sans préversion ni métadonnée." >&2
  usage
fi

printf '%s\n' "$VERSION" > VERSION

DIST_DIR="$PWD/dist"
APP_BUNDLE="$DIST_DIR/MRWatcher.app"
ZIP_PATH="$DIST_DIR/MRWatcher-v${VERSION}.zip"
DMG_PATH="$DIST_DIR/MRWatcher-v${VERSION}.dmg"
KEYCHAIN_ACCOUNT="com.goyan.mrwatcher.updates"

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"
rm -f "$ZIP_PATH" "$DMG_PATH"

MRWATCHER_APP_BUNDLE="$APP_BUNDLE" \
MRWATCHER_KILL_RUNNING_APP=0 \
MRWATCHER_VERSION="$VERSION" \
bash install.sh

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

SIGN_UPDATE="$(find .build -type f -name sign_update -perm -111 -print -quit)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "L'outil Sparkle sign_update est introuvable." >&2
  exit 1
fi

SIGNATURE="$("$SIGN_UPDATE" --account "$KEYCHAIN_ACCOUNT" -p "$ZIP_PATH")"
if [[ -z "$SIGNATURE" ]]; then
  echo "Sparkle n'a pas retourné de signature EdDSA." >&2
  exit 1
fi

FILE_LENGTH="$(stat -f '%z' "$ZIP_PATH")"
RELEASE_URL="https://github.com/goyan/mr-watcher/releases/download/v${VERSION}/MRWatcher-v${VERSION}.zip"

cat > appcast.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MR Watcher updates</title>
    <link>https://github.com/goyan/mr-watcher</link>
    <description>MR Watcher application updates</description>
    <language>fr</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <enclosure
        url="${RELEASE_URL}"
        sparkle:version="${VERSION}"
        sparkle:shortVersionString="${VERSION}"
        sparkle:edSignature="${SIGNATURE}"
        length="${FILE_LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

DMG_STAGING="$(mktemp -d)"
trap 'rm -rf "$DMG_STAGING"' EXIT
ditto "$APP_BUNDLE" "$DMG_STAGING/MRWatcher.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "MRWatcher" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Archives créées :"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "Appcast mis à jour : appcast.xml"
