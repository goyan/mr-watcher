#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

ENV_FILE="$HOME/.env"

prompt_var() {
  local key="$1" label="$2" secret="${3:-false}"
  local current
  current=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)
  if [[ -n "$current" ]]; then
    if [[ "$secret" == "true" ]]; then
      echo "$key déjà configuré : ${current:0:8}…"
    else
      echo "$key déjà configuré : $current"
    fi
    read -r -p "Changer ? [laisser vide pour garder] : " val
    [[ -z "$val" ]] && return
  else
    if [[ "$secret" == "true" ]]; then
      read -rs -p "$label : " val; echo
    else
      read -r -p "$label : " val
    fi
  fi
  # Réécrire sans risque d'injection sed ni de corruption de newline
  grep -vE "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
  echo "${key}=${val}" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

echo "=== Configuration mr-watcher ==="
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

prompt_var GITLAB_PAT "GitLab Personal Access Token (scope minimal : read_api)" true
prompt_var GITLAB_HOST "GitLab host (ex: gitlab.factory.fonciamillenium.net)"
prompt_var GITLAB_USERNAME "Ton username GitLab (ex: herve.meunier.externe)"

echo "✓ Configuré dans $ENV_FILE (permissions 600)"
echo "Relance MRWatcher pour prendre en compte les changements."
