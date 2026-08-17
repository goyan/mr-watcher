# AGENTS.md — mr-watcher

## Règles pour tous les agents dans ce repo

### Délégation — OBLIGATOIRE

Tout changement de code Swift (fichiers `*.swift`) doit être délégué à un agent `coder`.
Même pour 1 ligne. Pas d'exception.

Après chaque agent `coder`, lancer un agent reviewer associé.

**Reviewer : utiliser `subagent_type: "claude"`, jamais `"code-reviewer"`** — ce dernier a `model: opus` hardcodé, désactivé sur ce compte (403).

**Réutiliser les agents existants** via `SendMessage(to: agentId)` pour les tâches successives sur les mêmes fichiers — le cache est chaud, moins de tokens. Spawner un nouvel agent uniquement si le contexte a trop dérivé. Note : `SendMessage` n'est pas disponible dans `subagent_type: "fork"`.

### Stack

- Swift 5.9, SwiftUI `MenuBarExtra(.menu)`, macOS 14+
- Swift Package Manager — une seule dépendance externe : Sparkle `2.9.5` (`.upToNextMinor`), pour les mises à jour signées EdDSA
- `@Observable @MainActor` pour le state (`StateStore`, `PollingScheduler`)
- `URLSessionConfiguration.ephemeral` (pas de cache disque du PAT)

### Conventions

- Ne jamais éditer directement les `.swift` — toujours via agent `coder`
- Après chaque `coder`, lancer `swift build -c release` puis `swift test` pour vérifier
- Après build propre, lancer `bash install.sh` pour déployer
- Ne jamais committer de PAT ou credentials
- Ne jamais committer la clé privée EdDSA (trousseau, compte `com.goyan.mrwatcher.updates`)

### Architecture

```
Sources/MRWatcher/
├── App.swift                  — @main, WindowGroup + MenuBarExtra(.menu), badge non-lus, activation .regular
├── ConfigManager.swift        — lit GITLAB_PAT/HOST/USERNAME depuis ~/.env ou Keychain (.env : régulier, 0600)
├── GitLabService.swift        — URLSession ephemeral async, GitLab API v4, PAT bloqué sur redirection inter-origine
├── JiraService.swift          — statut Jira par ticket via shell-out `acli` (issueKey validé)
├── PollingScheduler.swift     — poll toutes les N secondes (UserDefaults pollIntervalSeconds, plancher 15 s, défaut 60 s)
├── StateStore.swift           — @Observable @MainActor, diff CI/commentaires/approbations → events
├── NotificationService.swift  — UserNotifications macOS
├── MenuBarView.swift          — SwiftUI, menu de la barre de menus, liste MRs enrichies
├── StatusView.swift           — fenêtre principale (Dock) : tableau MRs, menu ⚙️, intervalle, version installée
├── SetupView.swift            — formulaire de configuration (PAT masqué)
├── SetupWindowController.swift — NSPanel hébergeant SetupView
└── UpdaterController.swift    — Sparkle `SPUStandardUpdaterController`, « Rechercher les mises à jour... »

Tests/MRWatcherTests/
└── RuntimeSecurityTests.swift — garde-fous sécurité runtime (redirection PAT, permissions .env)

scripts/
├── release.sh             — build SwiftPM propre, ZIP + DMG, signature et vérification de l'appcast
└── backup-update-key.sh   — export chiffré AES-256 de la clé EdDSA vers un support hors ligne
```

### GitLab API

- Liste MRs : `GET /api/v4/merge_requests?author_username=...&state=opened&per_page=50`
- Détail MR : `GET /api/v4/projects/:id/merge_requests/:iid?include_diverged_commits_count=true`
- Approvals : `GET /api/v4/projects/:id/merge_requests/:iid/approvals`
- Discussions : `GET /api/v4/projects/:id/merge_requests/:iid/discussions`
- Rebase : `POST /api/v4/projects/:id/merge_requests/:iid/notes` body `{"body":"/rebase"}` (quick action, préserve les approbations)

### PRD et Tracking

Maintenir `PRD.md` et `TRACKING.md` à jour après chaque feature ou bugfix.
