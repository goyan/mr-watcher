# MR Watcher

macOS menu bar app pour surveiller ses MRs GitLab en un coup d'œil.

## Ce que ça fait

Pour chaque MR ouverte, affiche en temps réel :

```
!56805  [millenium]  PROD-30914  ✅  ⬇74  ✅2/2  5j  [🟡 à tester]
```

| Indicateur | Signification |
|------------|---------------|
| `!IID` | Numéro de la MR (cliquable → ouvre GitLab) |
| `[projet]` | Repo : millenium · terragrunt · cortex… |
| `PROD-XXXXX` | Ticket Jira extrait de la branche ou du titre |
| CI | ✅ success · ❌ failed · 🔄 running · ⏳ pending |
| `⚠️` | Conflit de merge |
| `⬇N` | Commits de retard sur la branche cible |
| `👍/✅ N/N` | Approbations humaines (bots filtrés) |
| `💬N` | Threads non résolus |
| âge | Ancienneté de la MR |
| `[🟡/🟢 statut]` | Statut Jira du ticket associé (via `acli`) |

### Actions

- **↩ /rebase (N commits)** — rebase via quick action GitLab (préserve les approbations), déclenche automatiquement le job `build affected`
- **✕ Retirer** — retire une MR mergée de la liste
- **⚙️ Configurer…** — ouvre le panneau de configuration

### Notifications macOS

- ❌ CI échoué / ✅ CI réussi
- 💬 Nouveau commentaire
- 👍 Nouvelle approbation reçue
- ✅ MR passée de Draft → Ready
- 🎉 MR mergée

### Surveillance des MRs mergées

Les MRs mergées restent visibles avec l'icône `🔀` et un bouton `✕ Retirer` pour les archiver manuellement.

## Prérequis

- macOS 14+
- Swift 5.9+
- Un PAT GitLab avec les scopes `api` et `read_user`
- `acli` (Atlassian CLI) pour le statut Jira — optionnel

## Installation

```bash
git clone https://github.com/goyan/mr-watcher.git
cd mr-watcher
bash install.sh
open /Applications/MRWatcher.app
```

Configurer le PAT GitLab via **⚙️ Configurer…** dans le menu de l'app.

> **Note** : l'app est signée ad-hoc (pas notarisée Apple). Au premier lancement : clic droit → Ouvrir.

## Configuration

Variables lues depuis `~/.env` :

| Variable | Description |
|----------|-------------|
| `GITLAB_PAT` | Personal Access Token GitLab (scopes: `api`, `read_user`) |
| `GITLAB_HOST` | Host GitLab (ex: `gitlab.factory.fonciamillenium.net`) |
| `GITLAB_USERNAME` | Username GitLab (ex: `herve.meunier.externe`) |

Le statut Jira est récupéré via `acli` (Atlassian CLI) — aucune configuration supplémentaire si `acli` est déjà authentifié.

## Intervalle de poll

Par défaut 60 secondes. Configurable via :

```bash
defaults write MRWatcher pollIntervalSeconds 30
```

## Stack

- Swift 5.9 · SwiftUI `MenuBarExtra` · macOS 14+
- Swift Package Manager · zéro dépendance externe
- GitLab API v4 · Atlassian `acli` (Jira)
