# MR Watcher — Product Requirements

App macOS menu bar pour surveiller les MRs GitLab Millenium de l'auteur configuré et ses revues en cours.
Objectif : décider en un coup d'œil si une MR a besoin d'un ping Slack pour review/rebase/CI ou peut etre approuvee.

---

## Features

### Core — surveillance MRs

| # | Feature | Statut |
|---|---------|--------|
| F1 | Liste des MRs ouvertes (auteur configuré) | ✅ done |
| F2 | Numéro MR (`!IID`) + ticket Jira (`PROD-XXXXX`) | ✅ done |
| F3 | Statut CI (✅❌🔄⏳) via endpoint détail MR | ✅ done |
| F4 | Approbations humaines (`👍given/required`, bots filtrés) | ✅ done |
| F5 | Threads non résolus (`💬N`) | ✅ done |
| F6 | Commits de retard sur target branch (`⬇N`) | ✅ done |
| F7 | Âge de la MR (`Xj` / `Xh`) | ✅ done |
| F8 | Badge DRAFT | ✅ done |
| F9 | Label projet multi-repo (`[millenium]` / `[terragrunt]` / etc.) | ✅ done |
| F10 | Date de merge affichée avec âge inline (`Mergée: Xj`) et tooltip date complète en StatusView | ✅ done |
| F11 | MRs mergées conservées après redémarrage, jusqu'à `Retirer` | ✅ done |
| F12 | 10 dernières MRs mergées chargées depuis GitLab au démarrage | ✅ done |
| F13 | Onglet « Mes revues » : MRs ouvertes où l'utilisateur a commenté ou approuvé, avec auteur, statut Jira, CI, conflits, retard, approbations et threads personnels (créés ou auxquels il a participé)/autres | ✅ done |
| F14 | Découverte des revues depuis les événements GitLab, conservation locale des MRs encore ouvertes et rafraîchissement borné par rotation | ✅ done |
| F15 | Compteurs de threads personnels (créés ou auxquels l'utilisateur a participé) et externes actionnables : ouvrent directement le premier fil non résolu correspondant dans GitLab | ✅ done |
| F16 | Onglet « À revoir » : MRs ouvertes non-Draft d'autres auteurs portant un label GitLab configuré (repli `Indigo, indigo`), hors tickets Jira abandonnés | ✅ done |
| F17 | Priorisation des revues par gravité (à revalider > à reviewer > j'attends l'auteur > approuvée), pas par statut Jira : le groupement en sections `To Review`/`Les autres`/`Approved` est remplacé par des chips de filtre à compteurs (`Tout`, `À revalider`, `Mes fils`, `Sans revue`/`To Review` dans « À revoir », `Approuvées` dans « Mes revues ») sur une liste plate triée | ✅ done |
| F18 | Affichage GitLab immédiat des revues, avec `Chargement Jira` par MR pendant l'enrichissement, publication incrémentale sans état vide puis regroupement Jira asynchrone | ✅ done |
| F19 | Vue « Mes MRs » homogène avec les vues de revue (même table à colonnes, même langage de tags), et total de labels surveillés détaillé par statut Jira en pied de page | ✅ done |
| F20 | Chargement initial explicite, ticket Jira intégré aux métadonnées et auteur affiché en `Prénom N.`, y compris avec un pseudo GitLab technique | ✅ done |
| F21 | Rafraîchissement individuel d'une MR, avec mise à jour GitLab puis Jira sans poll global | ✅ done |
| F22 | Avertissement non bloquant Jira/acli avec détail assaini au survol, et info-bulles instantanées sur **toutes** les surfaces — fenêtre et panneau de barre de menus, 39 sur 39 dans ce dernier | ✅ done |
| F23 | Labels GitLab configurables pour alimenter « À revoir », avec repli `Indigo, indigo` | ✅ done |
| F24 | Notes de version embarquées et visibles au survol de la version installée | ✅ done |
| F25 | Actions de pipeline manuelles : lancer les tests (`build affected`) et l'auto review CI | ✅ done |
| F26 | Approbation bloquée jusqu'aux tests `build affected` verts ; auto review masquée après approbation de Claude | ✅ done |
| F27 | Signal orange actionnable « À revalider · N fils » lorsqu'un commit de tête est postérieur au dernier commentaire personnel d'un fil non résolu | ✅ done |
| F28 | Tags sémantiques compacts et colorés pour Jira, CI, conflits, retards, approbations et fils dans les deux vues de monitoring | ✅ done |
| F29 | Signal « À revalider » ouvre directement la première note d’un fil personnel nécessitant une revalidation dans les deux vues | ✅ done |
| F30 | Vue tableau à colonnes pour les 3 onglets (largeurs alignées en-tête/lignes, rail de gravité, pastille État unique cliquable vers le pipeline CI quand l'état est piloté par la CI, colonne Votre implication en revue, tri par gravité figé, chips de filtre à compteurs) | ✅ done |
| F31 | URL Jira et préfixe de ticket configurables : sans URL, le ticket reste affiché mais n'est plus un lien ; le préfixe est échappé avant d'entrer dans la recherche | ✅ done |
| F32 | Avertissement « URL Jira non configurée » dans la fenêtre et le panneau, affiché seulement si un ticket est détecté sans URL renseignée, et ouvrant les réglages au clic | ✅ done |
| F33 | Ticket et statut Jira réunis en un seul tag (`PROD-12345 · Code review`) sur la ligne du titre, et cellule MR ramenée à une cible de clic unique occupant toute sa hauteur | ✅ done |
| F34 | Numéro de version toujours actionnable : un clic lance la recherche de mise à jour dans les deux vues, la pastille orange restant réservée à une mise à jour réellement disponible | ✅ done |

### Actions

| # | Feature | Statut |
|---|---------|--------|
| A1 | Clic → ouvre la MR dans le navigateur | ✅ done |
| A2 | `/rebase` via API GitLab (sans perdre les approbations) | ✅ done |
| A3 | Rafraîchir manuellement | ✅ done |
| A4 | Intervalle de poll réglable depuis l'UI (⚙️ → 15 s…24 h ou Jamais, défaut 10 min, redémarrage du scheduler) | ✅ done |
| A5 | Approbation manuelle GitLab dans « Mes revues » et « À revoir » lorsque les threads créés par l'utilisateur ou auxquels il a participé sont résolus | ✅ done |
| A6 | Masquer durablement une MR revue depuis l'interface | ✅ done |
| A7 | Lancer les jobs GitLab manuels `build affected` et `auto review` lorsqu'ils sont jouables, sauf après approbation de Claude | ✅ done |

### Notifications

| # | Feature | Statut |
|---|---------|--------|
| N1 | Notification macOS sur CI failed/success | ✅ done |
| N2 | Notification sur nouveau commentaire | ✅ done |
| N3 | Badge numérique dans la barre de menu (non-lus) | ✅ done |
| N4 | Déduplication des notifications (identifiant stable) | ✅ done |
| N5 | Notification nouvelle approbation | ✅ done |
| N6 | Notification MR prête (draft → ready) | ✅ done |
| N7 | Notification MR mergée 🎉 | ✅ done |

### Infrastructure

| # | Feature | Statut |
|---|---------|--------|
| I1 | Auth : PAT depuis `~/.env` ou Keychain | ✅ done |
| I2 | Poll configurable (défaut 10 min, désactivation persistante possible) | ✅ done |
| I3 | Session URLSession ephémère (pas de cache disque du PAT) | ✅ done |
| I4 | `@MainActor` isolation (pas de data race) | ✅ done |
| I5 | `install.sh` + codesign ad-hoc | ✅ done |
| I6 | `setup.sh` interactif (PAT masqué, chmod 600) | ✅ done |
| I7 | Icône d'application incluse dans le bundle macOS | ✅ done |
| I8 | Application visible dans le Dock tout en conservant le menu bar extra | ✅ done |
| I9 | Mise à jour manuelle Sparkle : ZIP et appcast EdDSA signés, vérifiés avant extraction | ✅ done |
| I10 | Version installée affichée dans le pied de la fenêtre principale | ✅ done |
| I11 | Sécurité runtime : PAT sans redirection inter-origine et `.env` privé vérifié | ✅ done |
| I13 | Aucune valeur d'employeur codée en dur : hôte GitLab par défaut vide, URL Jira et préfixe de ticket en réglages locaux | ✅ done |
| I12 | Panneau de barre de menus : vues À traiter/Toutes, cartes MR, actions contextuelles et états de survol | ✅ done |

---

## Backlog

| # | Feature | Priorité |
|---|---------|----------|
| B1 | ~~Feedback visuel après `/rebase` (succès / erreur)~~ | ✅ done |
| J1 | Statut Jira par MR via `acli` shell-out | ✅ done |
| J2 | Statut Jira conservé et rafraîchi pour les MRs mergées | ✅ done |
| B2 | Ping Slack depuis le menu (COPRO → #copro-daily-run, TRANSACTION → #transac-daily-run) | haute — en attente token Slack |
| B3 | ~~Filtrer/trier les MRs (par urgence : CI❌ > ⬇N > sans review)~~ | ✅ done — F30 |
| B4 | Support multi-auteurs (reviewer assigné à moi) | basse |
| B5 | ~~Intervalle de poll configurable via UI~~ | ✅ done — A4 |
| B6 | Login Items automatique à l'installation | basse |

## v0.5.9 — Fix approvals + Sparkle auto-check

| Fix | Description |
|-----|-------------|
| Approvals | `required = given + approvalsLeft` — aligne avec GitLab UI (était 0/3 au lieu de 0/2) |
| Sparkle | `SUEnableAutomaticChecks=true`, `SUScheduledCheckInterval=3600` — check auto toutes les heures |

## v0.5.10 — Redesign du panneau de barre de menus

| Évolution | Description |
|-----------|-------------|
| Panneau interactif | `MenuBarExtra(.window)` avec vue `À traiter` / `Toutes`, entête de synchronisation et pied compact |
| MRs structurées | Cartes à informations hiérarchisées, SF Symbols et actions GitLab/Jira distinctes |
| Actions | `/rebase` contextuel avec confirmation, retrait des MRs mergées, réglages, mise à jour et sortie conservés |
| Interaction | États de survol sur les MRs et leurs actions contextuelles |
