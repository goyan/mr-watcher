import AppKit
import SwiftUI

struct StatusView: View {
    let store: StateStore
    let scheduler: PollingScheduler
    let setupController: SetupWindowController

    @AppStorage("pollIntervalSeconds") private var pollIntervalSeconds = 60
    @State private var hoveredAction: MRKey?
    @State private var hoveredMR: MRKey?

    private var openedMRs: [MRSummary] {
        store.mrs
            .filter { $0.state == "opened" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var mergedMRs: [MRSummary] {
        store.mrs
            .filter { $0.state == "merged" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workList
            Divider()
            footer
        }
        .frame(
            minWidth: 760,
            idealWidth: 820,
            maxWidth: .infinity,
            minHeight: 600,
            idealHeight: 650,
            maxHeight: .infinity
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("MR Watcher", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            syncStatus

            Spacer()

            Button {
                Task { await scheduler.pollNow() }
            } label: {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Actualiser maintenant")
            .disabled(store.isLoading || !store.isConfigured)

            settingsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var syncStatus: some View {
        if !store.isConfigured {
            Label("Configuration requise", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if store.isLoading {
            Text("Synchronisation en cours")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let error = store.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .lineLimit(1)
        } else if let lastSync = store.lastSuccessfulPollAt {
            Text("Synchronisée à \(lastSync.formatted(date: .omitted, time: .shortened))")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("En attente de la première synchronisation")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button("Configurer...") {
                setupController.open(store: store, scheduler: scheduler)
            }

            Menu("Intervalle d'actualisation") {
                ForEach([15, 30, 60, 120, 300, 600], id: \.self) { seconds in
                    Button {
                        pollIntervalSeconds = seconds
                        scheduler.restart()
                    } label: {
                        if pollIntervalSeconds == seconds {
                            Label(intervalDescription(seconds), systemImage: "checkmark")
                        } else {
                            Text(intervalDescription(seconds))
                        }
                    }
                }
            }

            Divider()

            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Réglages")
    }

    @ViewBuilder
    private var workList: some View {
        if !store.isConfigured {
            ContentUnavailableView(
                "Configuration GitLab requise",
                systemImage: "arrow.triangle.branch",
                description: Text("Configurez GitLab pour afficher vos merge requests.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.mrs.isEmpty {
            ContentUnavailableView(
                "Aucune merge request",
                systemImage: "arrow.triangle.branch",
                description: Text("Les MRs ouvertes et récemment mergées apparaîtront ici.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !openedMRs.isEmpty {
                        mrSection(title: "Ouvertes (\(openedMRs.count))", mrs: openedMRs)
                    }

                    if !mergedMRs.isEmpty {
                        mrSection(title: "Récemment mergées (\(mergedMRs.count))", mrs: mergedMRs)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mrSection(title: String, mrs: [MRSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ForEach(mrs) { mr in
                mrRow(mr)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                Divider()
                    .padding(.horizontal, 16)
            }
        }
    }

    private var footer: some View {
        HStack {
            if store.lastError != nil {
                Button(store.lastErrorIsAuth ? "Reconfigurer..." : "Réessayer") {
                    if store.lastErrorIsAuth {
                        setupController.open(store: store, scheduler: scheduler)
                    } else {
                        Task { await scheduler.pollNow() }
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
            } else {
                Text("\(openedMRs.count) ouverte\(openedMRs.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                if !mergedMRs.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(mergedMRs.count) mergée\(mergedMRs.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Actualisation : \(intervalDescription(pollIntervalSeconds))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func mrRow(_ mr: MRSummary) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        return HStack(alignment: .top, spacing: 8) {
            Button {
                openURL(mr.webUrl)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    metadata(for: mr)

                    Text(mr.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir !\(mr.iid) dans GitLab")

            trailingActions(for: mr)
                .frame(width: 250, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(hoveredMR == key ? Color.secondary.opacity(0.10) : .clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovering in
            hoveredMR = isHovering ? key : nil
            isHovering ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
    }

    @ViewBuilder
    private func trailingActions(for mr: MRSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if let jira = store.jiraStatuses[MRKey(projectId: mr.projectId, iid: mr.iid)] {
                    jiraMetadata(jira, isOpen: mr.state == "opened")
                }
            }
            .frame(width: 132, alignment: .leading)

            actionButton(for: mr)
                .frame(width: 108, alignment: .trailing)
        }
        .font(.system(.callout, design: .monospaced))
        .lineLimit(1)
    }

    @ViewBuilder
    private func actionButton(for mr: MRSummary) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        if mr.state == "merged" {
            Button {
                store.dismiss(key: key)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hoveredAction == key ? Color.secondary.opacity(0.18) : .clear)
                    }
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { isHovering in
                hoveredAction = isHovering ? key : nil
                isHovering ? NSCursor.pointingHand.push() : NSCursor.pop()
            }
            .help("Retirer !\(mr.iid) de la liste")
        } else if let behind = mr.divergedCommitsCount, behind > 0, !mr.hasConflicts {
            Button {
                confirmRebase(for: mr)
            } label: {
                Label("/rebase", systemImage: "arrow.triangle.2.circlepath")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hoveredAction == key ? Color.secondary.opacity(0.18) : .clear)
                    }
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { isHovering in
                hoveredAction = isHovering ? key : nil
                isHovering ? NSCursor.pointingHand.push() : NSCursor.pop()
            }
            .help("Lancer /rebase pour !\(mr.iid) (\(behind) commits de retard)")
        }
    }

    private func metadata(for mr: MRSummary) -> some View {
        HStack(spacing: 8) {
            Text("!\(mr.iid)")
                .fontWeight(.semibold)

            Text("[\(projectName(for: mr))]")

            if let ticket = ticket(for: mr) {
                Text(ticket)
            }

            stateMetadata(for: mr)
        }
        .font(.system(.callout, design: .monospaced))
        .lineLimit(1)
    }

    @ViewBuilder
    private func stateMetadata(for mr: MRSummary) -> some View {
        if mr.state == "merged" {
            Label("Mergée", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else {
            if mr.isDraft {
                Text("DRAFT")
                    .foregroundStyle(.secondary)
            }

            pipelineMetadata(for: mr)

            if mr.hasConflicts {
                Label("Conflit", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if let behind = mr.divergedCommitsCount, behind > 0 {
                Label("\(behind) commits de retard", systemImage: "arrow.down")
                    .foregroundStyle(.orange)
            }

            approvalMetadata(for: mr)
        }

        Text(ageString(mr.createdAt))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func pipelineMetadata(for mr: MRSummary) -> some View {
        switch mr.headPipeline?.status {
        case "success":
            Label("CI", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "failed":
            Label("CI", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case "running":
            Label("CI", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        case "pending":
            Label("CI", systemImage: "clock.fill")
                .foregroundStyle(.orange)
        case "canceled":
            Label("CI", systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary)
        case .some:
            Label("CI", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .none:
            Text("—")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func approvalMetadata(for mr: MRSummary) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        if let approval = store.approvals[key] {
            Label(
                "\(approval.given)/\(approval.required)",
                systemImage: approval.given >= approval.required ? "checkmark.circle.fill" : "hand.thumbsup.fill"
            )
            .foregroundStyle(approval.given >= approval.required ? .green : .secondary)

            if approval.unresolvedThreads > 0 {
                Label("\(approval.unresolvedThreads)", systemImage: "bubble.left.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func jiraMetadata(_ jira: JiraIssueStatus, isOpen: Bool) -> some View {
        Label(jira.name, systemImage: jiraSymbol(jira, isOpen: isOpen))
            .foregroundStyle(jiraColor(jira, isOpen: isOpen))
    }

    private func projectName(for mr: MRSummary) -> String {
        guard let url = URL(string: mr.webUrl) else { return "projet" }
        let segments = url.path.split(separator: "/")
        guard let dashIndex = segments.firstIndex(of: "-"), dashIndex > segments.startIndex else {
            return "projet"
        }
        return String(segments[segments.index(before: dashIndex)])
    }

    private func ticket(for mr: MRSummary) -> String? {
        ticket(in: mr.sourceBranch) ?? ticket(in: mr.title)
    }

    private func ticket(in value: String) -> String? {
        guard let range = value.range(of: #"PROD-\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    private func ageString(_ date: Date) -> String {
        let hours = Int(Date().timeIntervalSince(date) / 3_600)
        if hours < 1 { return "<1h" }
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)j"
    }

    private func jiraSymbol(_ jira: JiraIssueStatus, isOpen: Bool) -> String {
        if isOpen && jira.isStale {
            return "exclamationmark.triangle.fill"
        }
        switch jira.categoryKey {
        case "done": return "checkmark.circle.fill"
        case "new": return "circle"
        default: return "clock.fill"
        }
    }

    private func jiraColor(_ jira: JiraIssueStatus, isOpen: Bool) -> Color {
        if isOpen && jira.isStale {
            return .orange
        }
        switch jira.categoryKey {
        case "done": return .green
        case "new": return .blue
        default: return .orange
        }
    }

    private func intervalDescription(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func confirmRebase(for mr: MRSummary) {
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
                let oldPipelineId = mr.headPipeline?.id
                try await scheduler.rebase(projectId: mr.projectId, mrIid: mr.iid)
                try? await Task.sleep(for: .seconds(5))
                await scheduler.pollNow()
                await scheduler.triggerBuildAffected(
                    projectId: mr.projectId,
                    mrIid: mr.iid,
                    oldPipelineId: oldPipelineId
                )
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
}
