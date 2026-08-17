import SwiftUI
import AppKit

struct MenuBarView: View {
    let store: StateStore
    let scheduler: PollingScheduler
    let setupController: SetupWindowController
    let onClearEvents: () -> Void

    var body: some View {
        headerSection
        Divider()
        if store.isConfigured {
            Button("⚙️ Configurer…") { setupController.open(store: store, scheduler: scheduler) }
            Divider()
        }
        contentSection
        Divider()
        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Text("MR Watcher").font(.headline)
            Spacer()
            Button(action: { Task { await scheduler.pollNow() } }) {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if !store.isConfigured {
            Button("⚙️ Configuration requise…") { setupController.open(store: store, scheduler: scheduler) }
        } else {
            if let error = store.lastError {
                Text("⚠️ \(error)").foregroundStyle(.red).font(.caption)
                if store.lastErrorIsAuth {
                    Button("Reconfigurer…") { setupController.open(store: store, scheduler: scheduler) }
                        .font(.caption)
                }
                Divider()
            }
            eventsSection
            mrsSection
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if !store.events.isEmpty {
            Text("Événements récents").font(.caption).foregroundStyle(.secondary)
            ForEach(store.events.prefix(5)) { event in
                Button(action: { openURL(event.webUrl) }) {
                    Label(truncated(event.mrTitle, 48), systemImage: eventIcon(event.kind))
                }
            }
            Button("✕ Effacer les événements") { onClearEvents(); store.clearEvents() }
                .font(.caption)
            Divider()
        }
    }

    @ViewBuilder
    private var mrsSection: some View {
        let opened = store.mrs.filter { $0.state == "opened" }.sorted { $0.createdAt > $1.createdAt }
        let merged = store.mrs.filter { $0.state == "merged" }.sorted { $0.createdAt > $1.createdAt }

        if !opened.isEmpty {
            Text("Ouvertes (\(opened.count))").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(opened.enumerated()), id: \.element.id) { idx, mr in
                if idx > 0 { Divider() }
                mrRow(mr)
            }
        }

        if !merged.isEmpty {
            if !opened.isEmpty { Divider() }
            Text("Récemment mergées (\(merged.count))").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(merged.enumerated()), id: \.element.id) { idx, mr in
                if idx > 0 { Divider() }
                mrRow(mr)
            }
        }
    }

    @ViewBuilder
    private func mrRow(_ mr: MRSummary) -> some View {
        // Ligne 1 : cliquable — IID · PROD · CI · approvals · âge
        Button(action: { openURL(mr.webUrl) }) {
            Text(headerLine(mr))
                .font(.system(size: 11, design: .monospaced))
        }
        // Ligne 2 : titre (non cliquable, visuel uniquement)
        Text("  " + truncated(mr.title, 52))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        // Bouton "Retirer" — uniquement pour les MRs mergées
        if mr.state == "merged" {
            Button("  ✕ Retirer") {
                store.dismiss(key: MRKey(projectId: mr.projectId, iid: mr.iid))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        // Bouton rebase — visible uniquement si la branche est en retard et non mergée
        if let behind = mr.divergedCommitsCount, behind > 0, !mr.hasConflicts {
            Button("  ↩ /rebase (\(behind) commits)") {
                let alert = NSAlert()
                alert.messageText = "Lancer le rebase ?"
                alert.informativeText = "Rebase de !\(mr.iid) — réécrit l'historique et force-push la branche source."
                alert.addButton(withTitle: "Rebase")
                alert.addButton(withTitle: "Annuler")
                alert.alertStyle = .warning
                alert.buttons.last?.keyEquivalent = "\u{1b}"
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Task {
                    do {
                        // Capturer l'id du pipeline AVANT le rebase
                        let oldPipelineId = mr.headPipeline?.id
                        try await scheduler.rebase(projectId: mr.projectId, mrIid: mr.iid)
                        try? await Task.sleep(for: .seconds(5))
                        await scheduler.pollNow()
                        // Tenter de déclencher build affected sur le nouveau pipeline
                        await scheduler.triggerBuildAffected(projectId: mr.projectId, mrIid: mr.iid, oldPipelineId: oldPipelineId)
                    } catch {
                        store.lastError = "Rebase !\(mr.iid) : \(error.localizedDescription)"
                        NotificationService.shared.notify(
                            identifier: "rebase-\(mr.projectId)-\(mr.iid)",
                            title: "Rebase échoué — !\(mr.iid)",
                            body: error.localizedDescription,
                            url: mr.webUrl
                        )
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Formatage ligne header

    private func headerLine(_ mr: MRSummary) -> String {
        var parts: [String] = []

        // IID
        parts.append("!\(mr.iid)")

        // Nom du projet depuis web_url : .../fonciamillenium/PROJECT/-/merge_requests/...
        if let projectName = extractProjectName(from: mr.webUrl) {
            parts.append("[\(projectName)]")
        }

        // Ticket PROD
        if let ticket = extractTicketFromMR(mr) {
            parts.append(ticket)
        }

        // Draft
        if mr.isDraft { parts.append("[DRAFT]") }

        // CI
        if let status = mr.headPipeline?.status {
            parts.append(ciEmoji(status))
        } else {
            parts.append("—")
        }

        // Conflits
        if mr.hasConflicts { parts.append("⚠️") }

        // Commits de retard
        if let behind = mr.divergedCommitsCount, behind > 0 {
            parts.append("⬇\(behind)")
        }

        // Approvals
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        if let appr = store.approvals[key] {
            let icon = appr.given >= appr.required ? "✅" : "👍"
            parts.append("\(icon)\(appr.given)/\(appr.required)")
            if appr.unresolvedThreads > 0 {
                parts.append("💬\(appr.unresolvedThreads)")
            }
        }

        // Âge
        parts.append("Créée: \(ageString(mr.createdAt))")
        if mr.state == "merged", let mergedAt = mr.mergedAt {
            parts.append("Mergée: \(ageString(mergedAt))")
        }

        // Statut Jira
        if let jira = store.jiraStatuses[key] {
            let icon = mr.state == "opened" && jira.isStale ? "⚠️PROD" : jiraEmoji(jira.categoryKey)
            parts.append("[\(icon) \(jira.name)]")
        }

        return parts.joined(separator: "  ")
    }

    private func jiraEmoji(_ categoryKey: String) -> String {
        switch categoryKey {
        case "done": return "🟢"
        case "new":  return "🔵"
        default:     return "🟡"   // indeterminate = en cours
        }
    }

    // MARK: - Helpers

    private func extractProjectName(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        // path = /group/project/-/merge_requests/IID
        if let dashIdx = segments.firstIndex(of: "-"), dashIdx >= 2 {
            return segments[dashIdx - 1]
        }
        return segments.count >= 2 ? segments[1] : nil
    }

    private func extractTicket(_ branch: String) -> String? {
        guard let range = branch.range(of: #"PROD-\d+"#, options: .regularExpression) else { return nil }
        return String(branch[range])
    }

    private func extractTicketFromMR(_ mr: MRSummary) -> String? {
        extractTicket(mr.sourceBranch) ?? extractTicket(mr.title)
    }

    private func ciEmoji(_ status: String) -> String {
        switch status {
        case "success":  return "✅"
        case "failed":   return "❌"
        case "running":  return "🔄"
        case "pending":  return "⏳"
        case "canceled": return "⊘"
        default:         return "○"
        }
    }

    private func ageString(_ date: Date) -> String {
        let h = Int(Date().timeIntervalSince(date) / 3600)
        if h < 1  { return "<1h" }
        if h < 24 { return "\(h)h" }
        return "\(h / 24)j"
    }

    private static let dateFormatterCurrentYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    private static let dateFormatterOtherYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "?" }
        let formatter = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
            ? Self.dateFormatterCurrentYear
            : Self.dateFormatterOtherYear
        return formatter.string(from: date)
    }

    private func eventIcon(_ kind: WatchEventKind) -> String {
        switch kind {
        case .ciFailure:   return "xmark.circle.fill"
        case .ciSuccess:   return "checkmark.circle.fill"
        case .newComment:  return "bubble.left.fill"
        case .merged:      return "checkmark.seal.fill"
        case .newApproval: return "hand.thumbsup.fill"
        case .mrReady:     return "checkmark.circle.fill"
        }
    }

    private func truncated(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
