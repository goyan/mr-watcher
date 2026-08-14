#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
KEYCHAIN_SERVICE="https://sparkle-project.org"
KEYCHAIN_ACCOUNT="com.goyan.mrwatcher.updates"

usage() {
  echo "Usage: $0 /chemin/absolu/nom.mrwatcher-update-key.enc" >&2
  exit 64
}

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
    [[ ! -L "$current" ]] || fail "Emplacement refusé : composant symbolique détecté ($current)."
  done
}

[[ $# -eq 1 ]] || usage
OUTPUT_INPUT="$1"
[[ "$OUTPUT_INPUT" == /* ]] || fail "Le fichier de sauvegarde doit être indiqué par un chemin absolu."

OUTPUT_DIR_INPUT="$(dirname "$OUTPUT_INPUT")"
OUTPUT_NAME="$(basename "$OUTPUT_INPUT")"
[[ "$OUTPUT_NAME" == *.mrwatcher-update-key.enc ]] || fail "Le fichier doit se terminer par .mrwatcher-update-key.enc."
[[ -d "$OUTPUT_DIR_INPUT" ]] || fail "Le répertoire de destination n'existe pas : $OUTPUT_DIR_INPUT"
assert_no_symlink_components "$OUTPUT_DIR_INPUT"

OUTPUT_DIR="$(cd -P "$OUTPUT_DIR_INPUT" && pwd -P)"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_NAME"
case "$OUTPUT_PATH/" in
  "$REPO_ROOT/"*) fail "La sauvegarde doit rester hors du dépôt." ;;
esac

[[ ! -e "$OUTPUT_PATH" && ! -L "$OUTPUT_PATH" ]] || fail "Le fichier de sortie existe déjà : $OUTPUT_PATH"
[[ "$(stat -f '%Su' "$OUTPUT_DIR")" == "$(id -un)" ]] || fail "Le répertoire de destination doit vous appartenir."
OUTPUT_MODE="$(stat -f '%Lp' "$OUTPUT_DIR")"
OUTPUT_MODE=$((8#$OUTPUT_MODE))
(( (OUTPUT_MODE & 0077) == 0 )) || fail "Le répertoire de destination doit être privé (chmod 700)."

umask 077
SECRET_FILE=""
ENCRYPTED_FILE=""
PASSPHRASE=""
cleanup() {
  PASSPHRASE=""
  [[ -z "$SECRET_FILE" ]] || rm -f "$SECRET_FILE"
  [[ -z "$ENCRYPTED_FILE" ]] || rm -f "$ENCRYPTED_FILE"
}
trap cleanup EXIT HUP INT TERM

SECRET_FILE="$(mktemp "$OUTPUT_DIR/.mrwatcher-update-key.XXXXXX")"
ENCRYPTED_FILE="$(mktemp "$OUTPUT_DIR/.mrwatcher-update-key.XXXXXX")"
chmod 600 "$SECRET_FILE" "$ENCRYPTED_FILE"

security find-generic-password \
  -s "$KEYCHAIN_SERVICE" \
  -a "$KEYCHAIN_ACCOUNT" \
  -w > "$SECRET_FILE"

SECRET_LENGTH="$(wc -c < "$SECRET_FILE" | tr -d '[:space:]')"
[[ "$SECRET_LENGTH" == "44" || "$SECRET_LENGTH" == "128" ]] || fail "La donnée de clé récupérée est invalide."
LC_ALL=C grep -Eq '^[A-Za-z0-9+/=]+$' "$SECRET_FILE" || fail "La donnée de clé récupérée est invalide."

read -r -s -p "Passphrase de sauvegarde : " PASSPHRASE
echo
[[ -n "$PASSPHRASE" ]] || fail "La passphrase ne peut pas être vide."
read -r -s -p "Confirmez la passphrase : " PASSPHRASE_CONFIRMATION
echo
[[ "$PASSPHRASE" == "$PASSPHRASE_CONFIRMATION" ]] || fail "Les passphrases ne correspondent pas."
PASSPHRASE_CONFIRMATION=""

openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt \
  -in "$SECRET_FILE" \
  -out "$ENCRYPTED_FILE" \
  -pass fd:3 3<<< "$PASSPHRASE"

ln "$ENCRYPTED_FILE" "$OUTPUT_PATH" || fail "Impossible de créer le fichier de sortie sans écrasement."
chmod 600 "$OUTPUT_PATH"
rm -f "$ENCRYPTED_FILE"
ENCRYPTED_FILE=""

echo "Sauvegarde chiffrée créée : $OUTPUT_PATH"
