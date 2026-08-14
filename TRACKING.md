# MR Watcher — Tracking

## État actuel

- **Version** : 1.0-dev
- **Build** : ✅ `swift build -c release` propre
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
