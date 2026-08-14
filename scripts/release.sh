#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

usage() {
  echo "Usage: $0 <version-semver>" >&2
  echo "       MRWATCHER_RELEASE_DRY_RUN=1 $0 <version-semver>" >&2
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

fail() {
  echo "$*" >&2
  exit 1
}

require_clean_worktree() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Le helper doit être exécuté dans un dépôt Git."
  [[ -z "$(git status --porcelain=v1)" ]] || fail "Worktree ou index non propre : annulez/stashez les changements avant une release."
}

require_unreleased_tag() {
  local tag="v$VERSION"
  if git show-ref --verify --quiet "refs/tags/$tag"; then
    fail "Le tag local $tag existe déjà."
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    local remote_status
    set +e
    git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1
    remote_status=$?
    set -e
    case "$remote_status" in
      0) fail "Le tag distant $tag existe déjà." ;;
      2) ;;
      *) fail "Impossible de vérifier les tags distants ; abandon de la release." ;;
    esac
  fi
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

validate_sparkle_tools() {
  [[ -x "$SIGN_UPDATE" ]] || fail "L'outil Sparkle sign_update est introuvable : $SIGN_UPDATE"
  [[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]] || fail "L'artefact Sparkle 2.9 est introuvable : $SPARKLE_FRAMEWORK_SOURCE"
  [[ -f "$SPARKLE_FRAMEWORK_INFO" ]] || fail "Info.plist Sparkle introuvable : $SPARKLE_FRAMEWORK_INFO"

  local sparkle_version
  sparkle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SPARKLE_FRAMEWORK_INFO")"
  [[ "$sparkle_version" == 2.9.* ]] || fail "Version Sparkle inattendue : $sparkle_version (2.9.x requise)."
}

DRY_RUN="${MRWATCHER_RELEASE_DRY_RUN:-0}"
[[ "$DRY_RUN" == "0" || "$DRY_RUN" == "1" ]] || fail "MRWATCHER_RELEASE_DRY_RUN doit valoir 0 ou 1."

DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/MRWatcher.app"
ZIP_PATH="$DIST_DIR/MRWatcher-v${VERSION}.zip"
DMG_PATH="$DIST_DIR/MRWatcher-v${VERSION}.dmg"
KEYCHAIN_ACCOUNT="com.goyan.mrwatcher.updates"
SPARKLE_ARTIFACT_ROOT="$REPO_ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK_SOURCE="$SPARKLE_ARTIFACT_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FRAMEWORK_INFO="$SPARKLE_FRAMEWORK_SOURCE/Versions/B/Resources/Info.plist"
SIGN_UPDATE="$SPARKLE_ARTIFACT_ROOT/bin/sign_update"

require_clean_worktree
require_unreleased_tag
assert_no_symlink_components "$DIST_DIR"
[[ ! -e "$DIST_DIR" || -d "$DIST_DIR" ]] || fail "dist existe mais n'est pas un répertoire."

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Préflight release OK : v$VERSION est disponible et le worktree est propre."
  exit 0
fi

mkdir -p "$DIST_DIR"
assert_no_symlink_components "$DIST_DIR"
rm -f "$ZIP_PATH" "$DMG_PATH"
swift package clean
printf '%s\n' "$VERSION" > VERSION

MRWATCHER_APP_BUNDLE="$APP_BUNDLE" \
MRWATCHER_KILL_RUNNING_APP=0 \
MRWATCHER_VERSION="$VERSION" \
bash install.sh

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

validate_sparkle_tools
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
"$SIGN_UPDATE" --account "$KEYCHAIN_ACCOUNT" appcast.xml
"$SIGN_UPDATE" --account "$KEYCHAIN_ACCOUNT" --verify appcast.xml

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
echo "Appcast signé et vérifié : appcast.xml"
