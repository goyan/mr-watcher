# AGENTS.md — mr-watcher

## Règles pour tous les agents dans ce repo

### Délégation — OBLIGATOIRE

Tout changement de code Swift (fichiers `*.swift`) doit être délégué à un agent `coder`.
Même pour 1 ligne. Pas d'exception.

Après chaque agent `coder`, lancer un agent `code-reviewer` associé.

### Stack

- Swift 5.9, SwiftUI `MenuBarExtra(.menu)`, macOS 14+
- Swift Package Manager, zéro dépendance externe
- `@Observable @MainActor` pour le state (`StateStore`, `PollingScheduler`)
- `URLSessionConfiguration.ephemeral` (pas de cache disque du PAT)

### Conventions

- Ne jamais éditer directement les `.swift` — toujours via agent `coder`
- Après chaque `coder`, lancer `swift build -c release` pour vérifier
- Après build propre, lancer `bash install.sh` pour déployer
- Ne jamais committer de PAT ou credentials

### Architecture

```
Sources/MRWatcher/
├── App.swift               — @main, MenuBarExtra, badge non-lus
├── ConfigManager.swift     — lit GITLAB_PAT/HOST/USERNAME depuis ~/.env ou Keychain
├── GitLabService.swift     — URLSession async, GitLab API v4
├── PollingScheduler.swift  — poll toutes les N secondes (UserDefaults pollIntervalSeconds)
├── StateStore.swift        — @Observable @MainActor, diff CI/commentaires → events
├── NotificationService.swift — UserNotifications macOS
└── MenuBarView.swift       — SwiftUI, liste MRs enrichies
```

### GitLab API

- Liste MRs : `GET /api/v4/merge_requests?author_username=...&state=opened&per_page=50`
- Détail MR : `GET /api/v4/projects/:id/merge_requests/:iid?include_diverged_commits_count=true`
- Approvals : `GET /api/v4/projects/:id/merge_requests/:iid/approvals`
- Discussions : `GET /api/v4/projects/:id/merge_requests/:iid/discussions`
- Rebase : `POST /api/v4/projects/:id/merge_requests/:iid/notes` body `{"body":"/rebase"}` (quick action, préserve les approbations)

### PRD et Tracking

Maintenir `PRD.md` et `TRACKING.md` à jour après chaque feature ou bugfix.
