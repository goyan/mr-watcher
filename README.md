# MR Watcher

macOS menu bar app pour surveiller ses MRs GitLab en un coup d'œil, accessible aussi depuis le Dock.

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
- **Rechercher les mises à jour…** — vérifie et installe une release Sparkle signée

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

## Releases et mises à jour

Les mises à jour en application utilisent Sparkle et une signature EdDSA stockée dans le trousseau
de connexion macOS, sous le compte `com.goyan.mrwatcher.updates`. Ne supprimez pas cette clé :
elle est nécessaire pour signer les releases futures, mais ne doit jamais être exportée ou ajoutée
au dépôt.

Pour préparer une release :

```bash
bash scripts/release.sh 0.5.0
```

Le script produit `dist/MRWatcher-v0.5.0.zip` pour Sparkle et
`dist/MRWatcher-v0.5.0.dmg` pour l'installation manuelle, puis remplace `appcast.xml` par
l'entrée de la release et met `VERSION` à jour. Publiez d'abord les deux archives dans la release
GitHub `v0.5.0`, puis commitez et poussez `VERSION` et `appcast.xml` une fois le ZIP disponible.
Le ZIP doit rester inchangé après signature.

Un abonnement Apple Developer n'est pas nécessaire pour la signature EdDSA Sparkle. En revanche,
l'absence de signature Developer ID et de notarisation laisse Gatekeeper demander une autorisation
lors de la première installation.

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
- Swift Package Manager · Sparkle 2.9 pour les mises à jour signées
- GitLab API v4 · Atlassian `acli` (Jira)
