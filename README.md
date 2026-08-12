# MR Watcher

macOS menu bar app pour surveiller ses MRs GitLab en un coup d'œil.

## Ce que ça fait

Pour chaque MR ouverte, affiche en temps réel :

- `!IID  [projet]  PROD-XXXXX  CI  ⚠️  ⬇N  👍given/required  💬threads  âge`
- Statut CI : ✅ success · ❌ failed · 🔄 running · ⏳ pending
- Approbations humaines (bots GitLab filtrés automatiquement)
- Threads non résolus
- Commits de retard sur la branche cible
- Icône ⚠️ si conflit de merge
- Label `[projet]` pour distinguer millenium / terragrunt / cortex
- Notifications macOS sur CI failed/success et nouveaux commentaires
- Action `/rebase` via quick action GitLab (préserve les approbations)

## Prérequis

- macOS 14+
- Swift 5.9+
- Un PAT GitLab avec les scopes `api` et `read_user`

## Installation

```bash
# 1. Configurer le PAT et les variables GitLab
./setup.sh

# 2. Builder et installer
./install.sh
```

## Configuration

Variables lues depuis `~/.env` (priorité) ou Keychain (`mr-watcher`) :

| Variable | Description |
|----------|-------------|
| `GITLAB_PAT` | Personal Access Token GitLab (scopes: `api`, `read_user`) |
| `GITLAB_HOST` | Host GitLab (ex: `gitlab.factory.fonciamillenium.net`) |
| `GITLAB_USERNAME` | Ton username GitLab (ex: `herve.meunier.externe`) |

## Build manuel

```bash
swift build -c release
```

Le binaire est dans `.build/release/MRWatcher`.

## Intervalle de poll

Par défaut 60 secondes. Configurable via :

```bash
defaults write MRWatcher pollIntervalSeconds 30
```

## Stack

- Swift 5.9 · SwiftUI `MenuBarExtra` · macOS 14+
- Swift Package Manager · zéro dépendance externe
- GitLab API v4
