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
- **⚙️ Intervalle d'actualisation** — choisit la période de poll (15 s à 10 min), redémarre le scheduler
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

Les mises à jour en application utilisent Sparkle 2.9, avec une signature EdDSA du ZIP et du
feed `appcast.xml`. Le bundle exige un feed signé et Sparkle vérifie l'archive avant extraction.
La clé privée est stockée dans le trousseau de connexion macOS sous le compte
`com.goyan.mrwatcher.updates`. Ne la supprimez pas, ne la mettez jamais dans le dépôt et ne la
partagez jamais.

Pour préparer une release :

```bash
bash scripts/release.sh 0.5.0
```

Le script refuse un worktree/index non propre ou un tag local/distant `v0.5.0` déjà existant, puis
reconstruit SwiftPM depuis un état propre. Il produit `dist/MRWatcher-v0.5.0.zip` pour Sparkle et
`dist/MRWatcher-v0.5.0.dmg` pour l'installation manuelle, met `VERSION` à jour, signe
`appcast.xml` et vérifie cette signature. Un préflight sans écriture est disponible avec
`MRWATCHER_RELEASE_DRY_RUN=1 bash scripts/release.sh 0.5.0`. Publiez d'abord les deux archives
dans la release GitHub `v0.5.0`, puis commitez et poussez `VERSION` et `appcast.xml` une fois le ZIP
disponible. Le ZIP et le feed doivent rester inchangés après signature.

Le ZIP Sparkle signé est le canal de mise à jour recommandé. Sans certificat Developer ID ni
notarisation, le DMG public reste un installeur manuel sans authentification de l'éditeur : une
substitution avant la première installation ne peut pas être détectée de manière fiable. Gatekeeper
peut aussi demander une autorisation au premier lancement.

### Sauvegarde de la clé EdDSA

Conservez une sauvegarde chiffrée hors ligne de la clé de signature, dans un répertoire privé
(`chmod 700`) sur un support chiffré :

```bash
bash scripts/backup-update-key.sh /Volumes/Offline/mrwatcher-2026-08-14.mrwatcher-update-key.enc
```

Le script lit uniquement le compte Keychain `com.goyan.mrwatcher.updates`, demande une passphrase,
crée un fichier AES-256 chiffré avec PBKDF2 et ne l'écrase jamais. Il ne doit pas être exécuté dans
le dépôt ou vers un stockage synchronisé. Conservez séparément la passphrase et le support.

Pour restaurer sur un Mac de récupération, déchiffrez temporairement le fichier dans un répertoire
privé, importez-le avec l'outil Sparkle 2.9 et supprimez immédiatement le fichier temporaire :

```bash
umask 077
temporary_key="$(mktemp)"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 \
  -in /Volumes/Offline/mrwatcher-2026-08-14.mrwatcher-update-key.enc \
  -out "$temporary_key"
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.goyan.mrwatcher.updates -f "$temporary_key"
rm -f "$temporary_key"
```

Effectuez cette opération sur une machine de récupération contrôlée. Le fichier temporaire est une
clé privée en clair ; le chiffrement de disque doit être actif.

## Configuration

Variables lues depuis `~/.env` :

| Variable | Description |
|----------|-------------|
| `GITLAB_PAT` | Personal Access Token GitLab (scopes: `api`, `read_user`) |
| `GITLAB_HOST` | Host GitLab (ex: `gitlab.factory.fonciamillenium.net`) |
| `GITLAB_USERNAME` | Username GitLab (ex: `herve.meunier.externe`) |

Le statut Jira est récupéré via `acli` (Atlassian CLI) — aucune configuration supplémentaire si `acli` est déjà authentifié.

## Intervalle de poll

Par défaut 60 secondes. Réglable depuis la fenêtre principale : **⚙️ → Intervalle d'actualisation**
(15 s · 30 s · 1 min · 2 min · 5 min · 10 min). Le choix est persisté dans `UserDefaults` et le
scheduler redémarre immédiatement.

Équivalent en ligne de commande — l'intervalle est relu à chaque cycle, la nouvelle valeur
s'applique donc dès le poll suivant :

```bash
defaults write MRWatcher pollIntervalSeconds 30
```

Le plancher est de 15 secondes : toute valeur inférieure est ramenée à 15, et `0` (clé absente)
retombe sur 60.

## Stack

- Swift 5.9 · SwiftUI `MenuBarExtra` · macOS 14+
- Swift Package Manager · Sparkle 2.9 pour les mises à jour signées
- GitLab API v4 · Atlassian `acli` (Jira)
