# MR Watcher — Product Requirements

App macOS menu bar pour surveiller les MRs GitLab Millenium de l'auteur configuré.
Objectif : décider en un coup d'œil si une MR a besoin d'un ping Slack pour review/rebase/CI.

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
| F10 | État mergé affiché par l'icône `🔀`, distincte des labels entre crochets | ✅ done |
| F11 | MRs mergées conservées après redémarrage, jusqu'à `Retirer` | ✅ done |
| F12 | 10 dernières MRs mergées chargées depuis GitLab au démarrage | ✅ done |

### Actions

| # | Feature | Statut |
|---|---------|--------|
| A1 | Clic → ouvre la MR dans le navigateur | ✅ done |
| A2 | `/rebase` via API GitLab (sans perdre les approbations) | ✅ done |
| A3 | Rafraîchir manuellement | ✅ done |

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
| I2 | Poll toutes les 60s | ✅ done |
| I3 | Session URLSession ephémère (pas de cache disque du PAT) | ✅ done |
| I4 | `@MainActor` isolation (pas de data race) | ✅ done |
| I5 | `install.sh` + codesign ad-hoc | ✅ done |
| I6 | `setup.sh` interactif (PAT masqué, chmod 600) | ✅ done |

---

## Backlog

| # | Feature | Priorité |
|---|---------|----------|
| B1 | ~~Feedback visuel après `/rebase` (succès / erreur)~~ | ✅ done |
| J1 | Statut Jira par MR via `acli` shell-out | ✅ done |
| J2 | Statut Jira conservé et rafraîchi pour les MRs mergées | ✅ done |
| B2 | Ping Slack depuis le menu (COPRO → #copro-daily-run, TRANSACTION → #transac-daily-run) | haute — en attente token Slack |
| B3 | Filtrer/trier les MRs (par urgence : CI❌ > ⬇N > sans review) | moyenne |
| B4 | Support multi-auteurs (reviewer assigné à moi) | basse |
| B5 | Intervalle de poll configurable via UI | basse |
| B6 | Login Items automatique à l'installation | basse |
