import AppKit
import SwiftUI

struct MenuBarView: View {
    private enum DisplayScope: String, CaseIterable, Identifiable {
        case needsAttention = "À traiter"
        case all = "Toutes"

        var id: Self { self }
    }

    private enum MRPriority {
        case critical
        case attention
        case neutral
        case complete

        var color: Color {
            switch self {
            case .critical: .red
            case .attention: .orange
            case .neutral: .secondary
            case .complete: .green
            }
        }

        var symbol: String {
            switch self {
            case .critical: "exclamationmark.circle.fill"
            case .attention: "exclamationmark.triangle.fill"
            case .neutral: "circle.fill"
            case .complete: "checkmark.circle.fill"
            }
        }
    }

    let store: StateStore
    let scheduler: PollingScheduler
    let setupController: SetupWindowController
    let updaterController: UpdaterController
    let onClearEvents: () -> Void

    @AppStorage("pollIntervalSeconds") private var pollIntervalSeconds = 60
    @State private var displayScope: DisplayScope = .needsAttention
    @State private var eventsExpanded = true
    @State private var mergedExpanded = false
    @State private var hoveredMR: MRKey?
    @State private var hoveredAction: MRKey?

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

    private var actionableMRs: [MRSummary] {
        openedMRs.filter(isActionable)
    }

    private var appVersion: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !version.isEmpty else {
            return "v--"
        }
        return "v\(version)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Vue des merge requests", selection: $displayScope) {
                ForEach(DisplayScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            content

            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 680, maxWidth: 760, minHeight: 420, idealHeight: 560, maxHeight: 680)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("MR Watcher", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            syncStatus
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await scheduler.pollNow() }
            } label: {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)
            .help("Actualiser maintenant")
            .accessibilityLabel("Actualiser les merge requests")
            .disabled(store.isLoading || !store.isConfigured)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var syncStatus: some View {
        if !store.isConfigured {
            Label("Configuration requise", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if store.isLoading {
            Text("Synchronisation…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if store.lastErrorIsAuth {
            Label("Connexion GitLab à reconfigurer", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else if store.lastError != nil {
            Label("Synchronisation échouée", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else if let lastPoll = store.lastSuccessfulPollAt {
            Text("Synchronisée \(lastPoll.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("En attente de synchronisation")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.isConfigured {
            configurationRequired
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let error = store.lastError {
                        errorNotice(error)
                    }

                    mrContent
                    eventsSection
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var configurationRequired: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Configuration GitLab requise")
                .font(.callout.weight(.semibold))
            Text("Connectez GitLab pour afficher vos merge requests.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Configurer…") {
                setupController.open(store: store, scheduler: scheduler)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorNotice(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(store.lastErrorIsAuth ? "La connexion GitLab doit être reconfigurée." : error)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(store.lastErrorIsAuth ? "Configurer…" : "Réessayer") {
                if store.lastErrorIsAuth {
                    setupController.open(store: store, scheduler: scheduler)
                } else {
                    Task { await scheduler.pollNow() }
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mrContent: some View {
        switch displayScope {
        case .needsAttention:
            if actionableMRs.isEmpty {
                emptyState(
                    title: openedMRs.isEmpty ? "Aucune merge request ouverte" : "Aucune action requise",
                    symbol: openedMRs.isEmpty ? "arrow.triangle.branch" : "checkmark.circle"
                )
            } else {
                mrSection(
                    title: "À traiter",
                    subtitle: "\(actionableMRs.count) merge request\(actionableMRs.count == 1 ? "" : "s")",
                    mrs: actionableMRs
                )
            }
        case .all:
            if openedMRs.isEmpty && mergedMRs.isEmpty {
                emptyState(title: "Aucune merge request", symbol: "arrow.triangle.branch")
            } else {
                if !openedMRs.isEmpty {
                    mrSection(
                        title: "Ouvertes",
                        subtitle: "\(openedMRs.count) merge request\(openedMRs.count == 1 ? "" : "s")",
                        mrs: openedMRs
                    )
                }

                if !mergedMRs.isEmpty {
                    DisclosureGroup(isExpanded: $mergedExpanded) {
                        mrGrid(mergedMRs)
                            .padding(.top, 6)
                    } label: {
                        sectionLabel(
                            title: "Récemment mergées",
                            subtitle: "\(mergedMRs.count) merge request\(mergedMRs.count == 1 ? "" : "s")"
                        )
                    }
                    .padding(8)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func emptyState(title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.semibold))
            if store.isLoading {
                Text("Les dernières données restent affichées pendant la synchronisation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func mrSection(title: String, subtitle: String, mrs: [MRSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title: title, subtitle: subtitle)
            mrGrid(mrs)
        }
    }

    private func sectionLabel(title: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mrGrid(_ mrs: [MRSummary]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 292), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(mrs) { mr in
                mrRow(mr)
            }
        }
    }

    private func mrRow(_ mr: MRSummary) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        let priority = priority(for: mr)

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: priority.symbol)
                .font(.caption)
                .foregroundStyle(priority.color)
                .frame(width: 12, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Button {
                    openURL(mr.webUrl)
                } label: {
                    HStack(spacing: 5) {
                        Text("!\(mr.iid)")
                            .font(.callout.weight(.semibold))
                        Text(projectName(for: mr))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(mr.title)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ouvrir la merge request !\(mr.iid), \(mr.title), dans GitLab")
                .help("Ouvrir !\(mr.iid) dans GitLab")

                metadataRow(for: mr)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            rowAction(for: mr, key: key)
        }
        .padding(8)
        .frame(minHeight: 72, alignment: .top)
        .background(
            hoveredMR == key ? Color.secondary.opacity(0.16) : Color(nsColor: .quaternaryLabelColor).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .contain)
        .onHover { isHovering in
            hoveredMR = isHovering ? key : nil
        }
    }

    @ViewBuilder
    private func jiraButton(for mr: MRSummary) -> some View {
        if let ticket = ticket(for: mr) {
            Button {
                openURL("https://fonciamillenium.atlassian.net/browse/\(ticket)")
            } label: {
                Label(ticket, systemImage: "ticket")
            }
            .buttonStyle(.plain)
            .foregroundStyle(jiraColor(for: mr))
            .help("Ouvrir \(ticket) dans Jira")
            .accessibilityLabel("Ouvrir le ticket \(ticket) dans Jira")
        }
    }

    private func metadataRow(for mr: MRSummary) -> some View {
        HStack(spacing: 7) {
            jiraButton(for: mr)
            pipelineMetadata(for: mr)
            approvalMetadata(for: mr)

            if let behind = mr.divergedCommitsCount, behind > 0 {
                Label("\(behind)", systemImage: "arrow.down")
                    .foregroundStyle(.orange)
                    .help("\(behind) commit\(behind == 1 ? "" : "s") de retard")
            }

            Label(ageString(mr.state == "merged" ? mr.mergedAt ?? mr.createdAt : mr.createdAt), systemImage: "clock")
                .foregroundStyle(.secondary)
                .help(mr.state == "merged" ? "Date de merge" : "Date de création")
        }
        .font(.caption2)
        .lineLimit(1)
    }

    @ViewBuilder
    private func pipelineMetadata(for mr: MRSummary) -> some View {
        switch mr.headPipeline?.status {
        case "success":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("CI réussie")
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("CI échouée")
        case "running":
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .help("CI en cours")
        case "pending":
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
                .help("CI en attente")
        case "canceled":
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .help("CI annulée")
        case .some:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .help("État CI inconnu")
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func approvalMetadata(for mr: MRSummary) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        if let approval = store.approvals[key] {
            Label(
                "\(approval.given)/\(approval.required)",
                systemImage: approval.given >= approval.required ? "checkmark.circle.fill" : "hand.thumbsup"
            )
            .foregroundStyle(approval.given >= approval.required ? .green : .secondary)
            .help("\(approval.given) approbation\(approval.given == 1 ? "" : "s") sur \(approval.required)")

            if approval.unresolvedThreads > 0 {
                Label("\(approval.unresolvedThreads)", systemImage: "bubble.left.fill")
                    .foregroundStyle(.orange)
                    .help("\(approval.unresolvedThreads) discussion\(approval.unresolvedThreads == 1 ? "" : "s") non résolue\(approval.unresolvedThreads == 1 ? "" : "s")")
            }
        }
    }

    @ViewBuilder
    private func rowAction(for mr: MRSummary, key: MRKey) -> some View {
        if mr.state == "merged" {
            Button {
                store.dismiss(key: key)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .background(
                        hoveredAction == key ? Color.secondary.opacity(0.24) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Retirer !\(mr.iid) de la liste")
            .accessibilityLabel("Retirer la merge request !\(mr.iid)")
            .onHover { isHovering in
                hoveredAction = isHovering ? key : nil
            }
        } else if let behind = mr.divergedCommitsCount, behind > 0, !mr.hasConflicts {
            Button {
                confirmRebase(for: mr)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .background(
                        hoveredAction == key ? Color.secondary.opacity(0.24) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .help("Lancer /rebase pour !\(mr.iid) (\(behind) commits de retard)")
            .accessibilityLabel("Lancer le rebase de la merge request !\(mr.iid)")
            .onHover { isHovering in
                hoveredAction = isHovering ? key : nil
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if !store.events.isEmpty {
            DisclosureGroup(isExpanded: $eventsExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.events.prefix(3)) { event in
                        Button {
                            openURL(event.webUrl)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: eventIcon(event.kind))
                                    .foregroundStyle(eventColor(event.kind))
                                    .frame(width: 14)
                                Text("!\(event.mrIid)")
                                    .fontWeight(.semibold)
                                Text(event.mrTitle)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text(ageString(event.createdAt))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir l'événement de !\(event.mrIid)")
                    }

                    Button(role: .destructive) {
                        onClearEvents()
                        store.clearEvents()
                    } label: {
                        Label("Effacer les événements", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.top, 6)
            } label: {
                sectionLabel(title: "Événements récents", subtitle: "\(store.events.count)")
            }
            .padding(8)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            settingsMenu

            Spacer()

            Text(footerStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if updaterController.updateAvailable {
                Button {
                    updaterController.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Mise à jour disponible")
                .accessibilityLabel("Installer la mise à jour disponible")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Quitter MR Watcher")
            .accessibilityLabel("Quitter MR Watcher")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsMenu: some View {
        Menu {
            Button("Configurer…") {
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

            Button("Rechercher les mises à jour…") {
                updaterController.checkForUpdates()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .help("Réglages")
        .accessibilityLabel("Réglages de MR Watcher")
    }

    private var footerStatus: String {
        if let lastPoll = store.lastSuccessfulPollAt {
            return "\(appVersion) · \(lastPoll.formatted(date: .omitted, time: .shortened))"
        }
        return appVersion
    }

    private func isActionable(_ mr: MRSummary) -> Bool {
        guard mr.state == "opened" else { return false }
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        let hasMissingApprovals = store.approvals[key].map { $0.given < $0.required } ?? false
        let hasThreads = store.approvals[key].map { $0.unresolvedThreads > 0 } ?? false
        return mr.hasConflicts
            || mr.headPipeline?.status == "failed"
            || (mr.divergedCommitsCount ?? 0) > 0
            || hasMissingApprovals
            || hasThreads
    }

    private func priority(for mr: MRSummary) -> MRPriority {
        if mr.hasConflicts || mr.headPipeline?.status == "failed" {
            return .critical
        }
        if isActionable(mr) {
            return .attention
        }
        if mr.state == "merged" || mr.headPipeline?.status == "success" {
            return .complete
        }
        return .neutral
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

    private func jiraColor(for mr: MRSummary) -> Color {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        guard let jira = store.jiraStatuses[key] else { return .secondary }
        if mr.state == "opened" && jira.isStale {
            return .orange
        }
        switch jira.categoryKey {
        case "done": return .green
        case "new": return .blue
        default: return .orange
        }
    }

    private func ageString(_ date: Date) -> String {
        let hours = Int(Date().timeIntervalSince(date) / 3_600)
        if hours < 1 { return "<1h" }
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)j"
    }

    private func eventIcon(_ kind: WatchEventKind) -> String {
        switch kind {
        case .ciFailure: "xmark.circle.fill"
        case .ciSuccess: "checkmark.circle.fill"
        case .newComment: "bubble.left.fill"
        case .merged: "checkmark.seal.fill"
        case .newApproval: "hand.thumbsup.fill"
        case .mrReady: "checkmark.circle.fill"
        }
    }

    private func eventColor(_ kind: WatchEventKind) -> Color {
        switch kind {
        case .ciFailure: .red
        case .newComment: .orange
        case .ciSuccess, .merged, .newApproval, .mrReady: .green
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
