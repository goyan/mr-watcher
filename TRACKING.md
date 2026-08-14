# MR Watcher — Tracking

## État actuel

- **Version** : 0.5.1 (release de test Sparkle)
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
| Bundle `MRWatcher.app` avec `Sparkle.framework`, appcast et signature ad-hoc | ✅ |
| Helper `scripts/release.sh <version>` : ZIP signé, DMG manuel, appcast | ✅ publié en v0.5.0, test v0.5.1 |
| Version installée dans le pied de la fenêtre principale | ✅ |

### Limites connues

| Sujet | Détail |
|-------|--------|
| Gatekeeper | Sans compte Apple Developer, la première installation non notarisée peut nécessiter clic droit → Ouvrir. |
| Clé EdDSA | La clé privée reste dans le trousseau de connexion sous `com.goyan.mrwatcher.updates`; sa perte empêche de signer les releases suivantes. |

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
10. Tester la mise à jour Sparkle de v0.5.0 vers v0.5.1
