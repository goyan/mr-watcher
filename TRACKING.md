# MR Watcher — Tracking

## État actuel

- **Version** : 0.5.10
- **Build** : ✅ `swift build -c release`, bundle Sparkle et archives signées publiés
- **Installé** : `/Applications/MRWatcher.app` (codesign ad-hoc)
- **PAT** : configuré dans `~/.env` (token glab Millenium)

---

## Session 2026-08-12

### Réalisé

| Quoi | Résultat |
|------|----------|
| Architecture Swift SPM macOS 14+ MenuBarExtra | ✅ |
| ConfigManager (env + Keychain), GitLabService, StateStore, PollingScheduler, NotificationService | ✅ |
| Affichage enrichi par MR : IID, PROD-ticket, CI, commits retard, approvals humaines, threads non résolus, âge | ✅ |
| Filtrage bots GitLab (`project_*_bot_*`) | ✅ |
| Action `/rebase` via API (PUT, sans perte d'approbations) | ✅ |
| Reviews de code : 4 reviewers × 2 passes → ~15 bugs critiques corrigés (data race, cache PAT, parsing .env, clé composite MRKey, etc.) | ✅ |
| Scripts `build.sh` / `install.sh` / `setup.sh` / `README.md` | ✅ |
| **Fix critique** : `diverged_commits_count` + CI via endpoint détail (`include_diverged_commits_count=true`) | ✅ |
| **Fix** : feedback rebase — NSAlert confirmation + propagation erreur + pollNow | ✅ |
| **Fix** : `LocalizedError` sur `MRWatcherError` (messages français) | ✅ |

### Issues connues / à faire

| # | Problème | Action |
|---|----------|--------|
| K1 | ~~Feedback rebase silencieux~~ | ✅ corrigé |
| K2 | ~~`diverged_commits_count` toujours nil~~ (endpoint liste ne le retourne pas) | ✅ corrigé via fetchMRDetail |
| K3 | ~~Review `a86dbd8`~~ | ✅ appliqué |
| K4 | ~~MRs multi-projet sans distinction~~ | ✅ F9 — label `[projet]` dans header |
| K5 | ~~Rebase via PUT API pouvait réinitialiser les approbations~~ | ✅ POST `/notes` avec quick action `/rebase` |
| K6 | ~~Bouton `/rebase` affiché même en cas de conflit~~ | ✅ masqué si `has_conflicts` |
| K7 | ~~`build affected` jouait l'ancien pipeline (race)~~ | ✅ retry loop 90s sur nouveau pipeline id |
| K8 | ~~Statut Jira disparaissait après merge~~ | ✅ rafraîchi pour les MRs mergées conservées à l’écran |
| K9 | ~~État mergé affiché comme statut entre crochets~~ | ✅ icône `🔀`, distincte des labels entre crochets |
| K10 | ~~MR mergée absente après redémarrage~~ | ✅ MRs mergées et retraits persistés dans `UserDefaults` |
| K11 | ~~MR mergée avant l'installation absente~~ | ✅ 10 dernières MRs mergées rechargées au démarrage |
| K12 | Icône générique dans le Dock lors de l'affichage de la configuration | ✅ icône bundle générée depuis `Assets/AppIcon.png` à l'installation |
| K13 | Application absente du Dock hors de la configuration | ✅ politique d'activation macOS `.regular` au lancement |
| K14 | Statuts Jira et actions de ligne désalignés | ✅ statut Jira aligné à gauche, colonne Actions élargie pour afficher `/rebase` entièrement |

---

## Session 2026-08-14

### Réalisé

| Quoi | Résultat |
|------|----------|
| Sparkle 2.9 intégré via SwiftPM | ✅ |
| Commande `Rechercher les mises à jour...` avec UI native Sparkle | ✅ |
| Bundle `MRWatcher.app` avec `Sparkle.framework`, feed signé et vérification avant extraction | ✅ |
| Helper `scripts/release.sh <version>` : build SwiftPM propre, ZIP/feed signés et vérifiés, DMG manuel | ✅ publié en v0.5.2 |
| Sauvegarde EdDSA chiffrée AES-256 | ✅ script opt-in, support hors ligne privé requis |
| Sécurité runtime | ✅ PAT bloqué sur redirection inter-origine, `.env` régulier propriétaire en 0600 |
| Version installée dans le pied de la fenêtre principale | ✅ |

### Limites connues

| Sujet | Détail |
|-------|--------|
| DMG manuel | Sans Developer ID ni notarisation, le DMG n'authentifie pas l'éditeur. Le ZIP Sparkle signé est le canal de mise à jour recommandé après l'installation initiale. |
| Clé EdDSA | La clé privée reste dans le trousseau de connexion sous `com.goyan.mrwatcher.updates`; la sauvegarde chiffrée hors ligne doit être conservée séparément. |

---

## Session 2026-08-17

### Réalisé

| Quoi | Résultat |
|------|----------|
| `MRSummary.mergedAt: Date?` décodé depuis `merged_at` GitLab API | ✅ |
| MenuBarView : `"Créée: Xj"` + `"Mergée: Xj"` dans `headerLine` (remplace `🔀` et âge brut) | ✅ |
| StatusView : idem + tooltip `formatDate` sur chaque date | ✅ |
| Fix tooltip StatusView : suppression `.help()` outer sur Button `mrRow` (masquait les `.help()` internes) | ✅ |
| `DateFormatter` static dans `MenuBarView` et `StatusView` (perf) | ✅ |
| `AGENTS.md` enrichi : seuil délégation, review inline, fork pattern | ✅ |

---

## Prochaines étapes suggérées

1. ~~Feedback `/rebase`~~ ✅
2. ~~F9 — label `[projet]`~~ ✅
3. ~~Conflits — icône ⚠️ + masque bouton rebase~~ ✅
4. ~~Build affected auto après rebase~~ ✅
5. ~~Surveillance MRs mergées (notification + badge + bouton Retirer)~~ ✅
6. **B2** Ping Slack — en attente token bot Slack
7. Tri MRs par urgence (CI❌ en premier)
8. ~~Push github.com/goyan/mr-watcher~~ ✅
9. ~~Publier une première release Sparkle signée (`appcast.xml` + ZIP + DMG)~~ ✅ v0.5.0
10. ~~Tester la mise à jour Sparkle de v0.5.0 vers v0.5.1~~ ✅

---

## Session 2026-08-17 (suite — v0.5.6)

### Réalisé

| Quoi | Résultat |
|------|----------|
| Fix tooltip dateRow : dates extraites hors du Button dans `dateRow(for:)` avec `.frame(maxWidth:.infinity)` + `.contentShape(Rectangle())` | ✅ |
| Tooltip quasi-instantané : `NSInitialToolTipDelay = 0.1` dans App.init | ✅ |

| v0.5.7 — revert NSInitialToolTipDelay (cassait les tooltips) | ✅ |

## Session 2026-08-17 (v0.5.8)

### Réalisé

| Quoi | Résultat |
|------|----------|
| Tooltip date instantané : remplacement `.help()` par `.onHover` overlay custom (`DateLabelView`) | ✅ |
| Zone de hover séparée par date (Créée / Mergée), overlay positionné au-dessus du texte | ✅ |
| App.swift : purge `UserDefaults NSInitialToolTipDelay` au lancement (nettoyage v0.5.6) | ✅ |

## Session 2026-08-18 (v0.5.9)

### Réalisé

| Quoi | Résultat |
|------|----------|
| Fix approvals : `required = given + approvalsLeft` (source de vérité GitLab, aligne avec l'UI) | ✅ |
| Sparkle auto-check : `SUEnableAutomaticChecks=true` + `SUScheduledCheckInterval=3600` dans install.sh | ✅ |

## Session 2026-08-18 (v0.5.10)

### Réalisé

| Quoi | Résultat |
|------|----------|
| Redesign du panneau de barre de menus | ✅ `MenuBarExtra(.window)` avec panneau interactif compact |
| Navigation | ✅ vues `À traiter` et `Toutes`, MRs mergées repliées |
| Lignes MR | ✅ cartes structurées, SF Symbols, accès GitLab et Jira séparés |
| Actions | ✅ refresh, `/rebase` confirmé, retrait, événements, réglages, mise à jour et sortie préservés |
| Feedback | ✅ survol de la MR et des actions contextuelles |
| Validation | ✅ build release, 5 tests runtime et installation locale |

---

## Session 2026-08-19

### Réalisé

| Quoi | Résultat |
|------|----------|
| Suivi des MRs commentées | ✅ Onglet « Mes revues » dans la fenêtre principale et le panneau de barre de menus |
| Signaux de décision | ✅ CI, conflits, retard de commits, approbations, threads personnels et autres threads ouverts |
| Approbation manuelle | ✅ action GitLab confirmée, visible seulement sans thread personnel ouvert et sans approbation existante |
| Navigation de thread | ✅ boutons « Mes fils » et « autres » avec survol, ouvrent l'ancre GitLab du premier fil non résolu correspondant |
| Cycle de vie des revues | ✅ suppression automatique si tous les commentaires personnels sont supprimés, croix de masquage persistante |
| Approbation | ✅ statut `Approved` vert après approbation personnelle |
| File à revoir | ✅ onglet `À revoir` pour les MRs des labels configurés (repli `Indigo, indigo`) ouvertes, non-Draft, d'autres auteurs, hors tickets Jira abandonnés et hors « Mes revues » |
| Priorisation Jira | ✅ groupes `To Review` puis `Les autres` dans les onglets de revue, avec statut texte visible ; dans « Mes revues », `Approved` est en bas sauf fil personnel ouvert |
| Enrichissement Jira différé | ✅ données GitLab publiées immédiatement ; chaque MR avec ticket affiche `Chargement Jira` pendant sa requête `acli`, puis reçoit son statut immédiatement sans état vide ; les listes sont reclassées à l'arrivée, avec rejet des réponses périmées |
| Cohérence des vues | ✅ cartes « Mes MRs » alignées sur les revues ; pied « À revoir » détaille total Indigo, `To Review` et `Les autres` |
| Finitions des cartes | ✅ chargement initial explicite, ticket Jira près de l’identification, auteur court `Prénom N.` dans toutes les listes, y compris pour les pseudos GitLab techniques |
| Découverte et charge | ✅ événements GitLab paginés et bornés, résolution des titres par lots de 8, MRs ouvertes persistées, rafraîchissement équitable par rotation |
| Robustesse | ✅ conservation du dernier état lors d'une erreur transitoire, éviction des MRs fermées ou introuvables |
| Validation technique | ✅ `swift build -c release` et `swift test` (5 tests), application installée et 6 revues réelles visibles dans les deux vues |
| Actions ciblées | ✅ bouton de rafraîchissement individuel sur chaque MR, avec chargement local sans cycle global |
| Approbation « À revoir » | ✅ action GitLab disponible selon les mêmes critères d’éligibilité que « Mes revues », sans action de masquage |
| Dégradation Jira | ✅ échec `acli` visible dans les deux barres de statut, détail assaini au survol, sans bloquer GitLab |
| Labels de revue | ✅ labels GitLab configurables dans Réglages, persistés localement et utilisés par « À revoir » |
| Notes de release | ✅ résumé embarqué dans le bundle, visible au survol de la version dans les deux vues |
| Tooltips d'action | ✅ overlays SwiftUI immédiats au-dessus des actions dans les deux vues, avec `.help` conservé en repli |
| Actions pipeline | ✅ lancement des jobs manuels `build affected` et `auto review`, avec pagination, annulation, garde de pipeline courant et masquage de l'auto review après approbation de Claude |
| Garde d'approbation | ✅ approbation après tests vérifiés/verts ; auto review indépendante dès que son job est manuel |
| Tooltips | ✅ panels AppKit immédiats, ancrés aux contrôles, non rognés et non interactifs (le premier clic reste disponible) |
| Polling | ✅ défaut 10 min ; options jusqu'à 24 h et « Jamais » (0 persistant), sans répétition automatique |
