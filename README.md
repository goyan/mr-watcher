# MR Watcher

macOS menu bar app pour surveiller ses MRs GitLab en un coup d'œil, accessible aussi depuis le Dock.

## Ce que ça fait

MR Watcher propose trois vues, dans la fenêtre principale comme dans le panneau de
barre de menus :

- **Mes MRs** : vos MRs ouvertes et récemment mergées.
- **Mes revues** : les MRs ouvertes sur lesquelles vous avez commenté ou que
  vous avez approuvées.
- **À revoir** : les MRs ouvertes, non-Draft, d'autres auteurs, correspondant aux
  labels GitLab configurés, hors tickets Jira abandonnés et hors **Mes revues**.

### Fenêtre principale — une table à colonnes

Chaque merge request occupe **une ligne**, et chaque information une **colonne
alignée d'une ligne à l'autre** : le regard descend une colonne pour comparer,
au lieu de lire chaque ligne. Un **rail de gravité** coloré borde la ligne à
gauche, doublé d'une **pastille d'état** qui nomme la prochaine action —
`Conflit`, `CI KO`, `Rebase requis`, `CI en cours`, `En attente de revue`,
`Prête à merger`. La couleur n'est jamais le seul porteur de sens.

L'ordre est **figé par urgence**, pas par date :

- **Mes MRs** : bloquée → en retard → fils ouverts → en attente d'approbation → prête.
- **Revues** : à revalider → à reviewer → j'attends l'auteur → approuvée, la plus
  vieille dette de review d'abord.

Les deux onglets de revue offrent des **chips de filtre à compteurs** (`Tout`,
`À revalider`, `Mes fils`, `Sans revue`, `To Review`, `Approuvées`) sur une liste
plate. Une chip à zéro reste affichée, grisée : les positions ne bougent jamais.
En revue, la colonne **Votre implication** répond à la seule question qui compte —
ce que *vous* avez à faire sur cette MR — et ses libellés ouvrent directement le
fil concerné dans GitLab.

Le **panneau de barre de menus** conserve son affichage compact en cartes, avec
le regroupement par statut Jira (**To Review** / **Les autres** / **Approved**).

Jira enrichit les données après le premier affichage GitLab afin de ne pas
bloquer l'interface. La MR interrogée affiche **Chargement Jira** jusqu'à la
publication immédiate de son statut, sans état vide intermédiaire.

Les tags sémantiques suivent la même palette partout : vert pour les états
positifs, orange pour l'attention, rouge pour les blocages, gris pour les états
neutres. Une donnée absente ne laisse **aucun** marqueur — la cellule reste vide.

Informations disponibles sur une ligne :

| Indicateur | Signification |
|------------|---------------|
| `!IID` | Numéro de la MR (cliquable → ouvre GitLab) |
| `[projet]` | Repo : millenium · terragrunt · cortex… |
| `PROD-XXXXX` | Ticket Jira extrait de la branche ou du titre |
| `CI OK` / `CI KO` / `CI en cours` | État du pipeline |
| `Conflit` | Conflit de merge |
| `N retards` | Commits de retard sur la branche cible |
| `N/N appro.` | Approbations humaines (bots filtrés) |
| `N fils` | Threads non résolus |
| `À revalider · N fils` | Un commit de tête est plus récent que votre dernier commentaire dans N fils personnels non résolus |
| âge | Ancienneté de la MR |
| `statut Jira` | Statut Jira du ticket associé (via `acli`) |
| `Jira...` | Statut Jira de la MR en cours de récupération |

### Actions

- **↻ Actualiser la MR** — met à jour uniquement la MR, ses discussions,
  approbations, CI, conflits, retard et statut Jira.
- **`Mes fils` / `autres`** — ouvre le premier thread non résolu correspondant
  directement dans GitLab. Un fil personnel est créé par vous ou contient une
  de vos réponses.
- **`À revalider · N fils`** — visible dans les revues lorsqu'un commit de tête
  est postérieur à votre dernier commentaire dans un fil personnel non résolu ;
  ouvre directement le premier fil personnel nécessitant une revalidation dans
  GitLab.
- **Approuver** — disponible pour une MR ouverte, non-Draft, non déjà
  approuvée, sans fil personnel ouvert et seulement après vérification que
  `build affected` est vert.
- **Lancer les tests** — disponible lorsque le job manuel GitLab
  `build affected` peut être joué.
- **Lancer l'auto review** — disponible indépendamment des tests lorsque son
  propre job GitLab est manuel, sauf si l'approbation GitLab de Claude est déjà
  présente.
- **↩ /rebase (N commits)** — rebase via quick action GitLab (préserve les approbations), déclenche automatiquement le job `build affected`
- **✕ Retirer** — retire une MR mergée de la liste
- **✕ Masquer** — retire durablement une MR de **Mes revues**.
- **⚙️ Configurer…** — ouvre le panneau de configuration
- **⚙️ Labels à surveiller** — configure les labels GitLab de la file
  **À revoir** (par défaut : `Indigo, indigo`).
- **⚙️ Intervalle d'actualisation** — réglé à 10 min par défaut, choisit une
  période de 15 s à 24 h, ou **Jamais** ; l'actualisation manuelle reste
  toujours disponible.
- **Rechercher les mises à jour…** — vérifie et installe une release Sparkle signée

Les actions affichent un tooltip immédiat au survol. Les notes de la release
installée sont disponibles au survol de son numéro de version.

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

Le runbook complet de préparation, signature, publication GitHub et vérification
post-release est dans [docs/RELEASE.md](docs/RELEASE.md). Pour un préflight :

```bash
MRWATCHER_RELEASE_DRY_RUN=1 bash scripts/release.sh <version>
```

Le script refuse un worktree/index non propre ou un tag local/distant déjà
existant, puis reconstruit SwiftPM depuis un état propre. Il produit un ZIP
Sparkle et un DMG, met `VERSION` à jour, signe `appcast.xml` et vérifie cette
signature.

Les notes de release sont maintenues dans `RELEASE_NOTES.md`, embarquées dans
l'application et publiées avec la release GitHub. Elles doivent décrire les
rubriques **Ajouts**, **Corrections** et **Validation** de la version concernée.

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
| `GITLAB_HOST` | Host GitLab (ex: `gitlab.exemple.com`) |
| `GITLAB_USERNAME` | Username GitLab (ex: `prenom.nom`) |

Le statut Jira est récupéré via `acli` (Atlassian CLI) — aucune configuration supplémentaire si `acli` est déjà authentifié. Si l'outil est absent ou échoue, GitLab continue de fonctionner et l'application affiche `Jira indisponible`; le détail assaini est disponible au survol.

Trois réglages supplémentaires sont enregistrés localement depuis
**⚙️ → Configurer…** :

- **Labels à surveiller** — alimentent l'onglet **À revoir**. Valeurs séparées
  par des virgules ou des retours à la ligne ; la casse est conservée, car
  GitLab distingue `Equipe` et `equipe`.
- **URL Jira** — la base de votre instance, par exemple
  `https://votre-org.atlassian.net`. Laissée vide, le ticket reste affiché mais
  n'est pas cliquable : l'application n'invente pas d'URL.
- **Préfixe de ticket** — le préfixe cherché dans le nom de branche puis dans le
  titre de la MR pour en déduire le ticket (`PROD` par défaut, donnant
  `PROD-12345`).

## Intervalle de poll

Par défaut 10 minutes. Réglable depuis la fenêtre principale ou le panneau de
barre de menus : **⚙️ → Intervalle d'actualisation**
(`15 s` · `30 s` · `1 min` · `2 min` · `5 min` · `10 min` · `1 h` · `4 h` ·
`8 h` · `24 h` · `Jamais`). Le choix est persisté dans `UserDefaults`.

**Jamais** désactive les répétitions automatiques. L'application effectue tout
de même son premier chargement au démarrage et les boutons d'actualisation
manuelle restent disponibles.

Équivalent en ligne de commande — l'intervalle est relu à chaque cycle, la nouvelle valeur
s'applique donc dès le poll suivant :

```bash
defaults write com.goyan.mrwatcher pollIntervalSeconds 600
```

Le plancher est de 15 secondes : toute valeur positive inférieure est ramenée à
15. La valeur `0` signifie **Jamais**; une clé absente utilise 600 secondes.

## Stack

- Swift 5.9 · SwiftUI `MenuBarExtra` · macOS 14+
- Swift Package Manager · Sparkle 2.9 pour les mises à jour signées
- GitLab API v4 · Atlassian `acli` (Jira)
