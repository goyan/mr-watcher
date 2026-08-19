import AppKit
import SwiftUI

struct ReviewSectionGroups {
    let toReview: [MRSummary]
    let others: [MRSummary]
    let approved: [MRSummary]

    init(
        mrs: [MRSummary],
        statuses: [MRKey: MRApprovals],
        jiraStatuses: [MRKey: JiraIssueStatus],
        separatesApproved: Bool
    ) {
        let approvedMRs = separatesApproved
            ? mrs.filter { mr in
                let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                guard let status = statuses[key] else { return false }
                return status.isApprovedByMe && status.myUnresolvedThreads == 0
            }
            : []
        approved = approvedMRs

        let approvedKeys = Set(
            approvedMRs.map { MRKey(projectId: $0.projectId, iid: $0.iid) }
        )
        let activeMRs = mrs.filter { mr in
            !approvedKeys.contains(MRKey(projectId: mr.projectId, iid: mr.iid))
        }
        toReview = activeMRs.filter { mr in
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            guard let status = jiraStatuses[key]?.name else { return false }
            return ["to review", "code review"].contains(
                status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }
        let toReviewKeys = Set(
            toReview.map { MRKey(projectId: $0.projectId, iid: $0.iid) }
        )
        others = activeMRs.filter { mr in
            !toReviewKeys.contains(MRKey(projectId: mr.projectId, iid: mr.iid))
        }
    }
}

struct StatusView: View {
    private enum ContentTab: String, CaseIterable, Identifiable {
        case myMRs = "Mes MRs"
        case myReviews = "Mes revues"
        case reviewable = "À revoir"

        var id: Self { self }
    }

    let store: StateStore
    let scheduler: PollingScheduler
    let setupController: SetupWindowController
    let updaterController: UpdaterController

    @AppStorage("pollIntervalSeconds") private var pollIntervalSeconds = 600
    @State private var contentTab: ContentTab = .myMRs
    @State private var hoveredAction: MRKey?
    @State private var hoveredPersonalThread: MRKey?
    @State private var hoveredOtherThread: MRKey?
    @State private var hoveredMR: MRKey?
    @State private var hoveredReviewDismissal: MRKey?

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

    private var reviewableToReviewCount: Int {
        store.reviewableMRs.filter(isToReview).count
    }

    private var reviewableOtherCount: Int {
        store.reviewableMRs.count - reviewableToReviewCount
    }

    private var appVersion: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !version.isEmpty else {
            return "Version indisponible"
        }
        return "v\(version)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentTabPicker
            Divider()
            content
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

            jiraWarning

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
            .immediateTooltip("Actualiser maintenant")
            .disabled(store.isLoading || !store.isConfigured)

            settingsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var contentTabPicker: some View {
        Picker("Contenu des merge requests", selection: $contentTab) {
            ForEach(ContentTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    @ViewBuilder
    private var jiraWarning: some View {
        if let error = store.jiraError {
            Label("Jira indisponible", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .help(error)
                .immediateTooltip(error)
                .accessibilityLabel("Jira indisponible : \(error)")
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button("Configurer...") {
                setupController.open(store: store, scheduler: scheduler)
            }

            Menu("Intervalle d'actualisation") {
                ForEach([15, 30, 60, 120, 300, 600, 3_600, 14_400, 28_800, 86_400, 0], id: \.self) { seconds in
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

            Button("Rechercher les mises à jour...") {
                updaterController.checkForUpdates()
            }

            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Réglages")
        .immediateTooltip("Réglages")
    }

    @ViewBuilder
    private var content: some View {
        switch contentTab {
        case .myMRs:
            workList
        case .myReviews:
            reviewList
        case .reviewable:
            reviewableList
        }
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
        } else if store.mrs.isEmpty && store.isLoading && store.lastSuccessfulPollAt == nil {
            loadingState
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

    @ViewBuilder
    private var reviewList: some View {
        if !store.isConfigured {
            ContentUnavailableView(
                "Configuration GitLab requise",
                systemImage: "arrow.triangle.branch",
                description: Text("Configurez GitLab pour afficher vos revues.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.reviewedMRs.isEmpty && store.isLoading && store.lastSuccessfulPollAt == nil {
            loadingState
        } else if store.reviewedMRs.isEmpty {
            ContentUnavailableView(
                "Aucune revue en cours",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Les MRs ouvertes sur lesquelles vous avez commente apparaitront ici.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    reviewSections(
                        for: store.reviewedMRs,
                        statuses: store.reviewStatuses,
                        showsActions: true,
                        separatesApproved: true
                    )
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var reviewableList: some View {
        if !store.isConfigured {
            ContentUnavailableView(
                "Configuration GitLab requise",
                systemImage: "arrow.triangle.branch",
                description: Text("Configurez GitLab pour afficher les MRs portant les labels configurés.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.reviewableMRs.isEmpty && store.isLoading && store.lastSuccessfulPollAt == nil {
            loadingState
        } else if store.reviewableMRs.isEmpty {
            ContentUnavailableView(
                "Aucune MR à revoir",
                systemImage: "eye",
                description: Text("Les MRs ouvertes portant les labels configurés apparaîtront ici.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    reviewSections(
                        for: store.reviewableMRs,
                        statuses: store.reviewableStatuses,
                        showsActions: true,
                        separatesApproved: false
                    )
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("Chargement des merge requests")
                .font(.headline)
            Text("Récupération des données GitLab...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chargement des merge requests, récupération des données GitLab")
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

    @ViewBuilder
    private func reviewSections(
        for mrs: [MRSummary],
        statuses: [MRKey: MRApprovals],
        showsActions: Bool,
        separatesApproved: Bool
    ) -> some View {
        let groups = ReviewSectionGroups(
            mrs: mrs,
            statuses: statuses,
            jiraStatuses: store.jiraStatuses,
            separatesApproved: separatesApproved
        )

        if !groups.toReview.isEmpty {
            reviewSection(
                title: "To Review",
                mrs: groups.toReview,
                statuses: statuses,
                showsActions: showsActions
            )
        }
        if !groups.others.isEmpty {
            reviewSection(
                title: "Les autres",
                mrs: groups.others,
                statuses: statuses,
                showsActions: showsActions
            )
        }
        if !groups.approved.isEmpty {
            reviewSection(
                title: "Approved",
                mrs: groups.approved,
                statuses: statuses,
                showsActions: showsActions
            )
        }
    }

    private func reviewSection(
        title: String,
        mrs: [MRSummary],
        statuses: [MRKey: MRApprovals],
        showsActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(mrs.count))")
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if !mrs.isEmpty {
                ForEach(mrs) { mr in
                    reviewRow(mr, statuses: statuses, showsActions: showsActions)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                    Divider()
                        .padding(.horizontal, 16)
                }
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
                if contentTab == .myMRs {
                    Text("\(openedMRs.count) ouverte\(openedMRs.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    if !mergedMRs.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(mergedMRs.count) mergée\(mergedMRs.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                } else if contentTab == .myReviews {
                    Text("\(store.reviewedMRs.count) revue\(store.reviewedMRs.count == 1 ? "" : "s") en cours")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(store.reviewableMRs.count) MR\(store.reviewableMRs.count == 1 ? "" : "s") à revoir")
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(reviewableToReviewCount) To Review")
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(reviewableOtherCount) Les autres")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if updaterController.updateAvailable {
                Button {
                    updaterController.checkForUpdates()
                } label: {
                    HStack(spacing: 4) {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .buttonStyle(.plain)
                .font(.callout)
                .help("Mise à jour disponible — cliquer pour installer\n\n\(ReleaseNotes.summary)")
                .immediateTooltip("Mise à jour disponible — cliquer pour installer\n\n\(ReleaseNotes.summary)")
                .accessibilityLabel("Version \(appVersion). Mise à jour disponible.")
            } else {
                Text(appVersion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(ReleaseNotes.summary)
                    .immediateTooltip(ReleaseNotes.summary)
                    .accessibilityLabel("Version \(appVersion). \(ReleaseNotes.summary)")
            }
            Text("·")
                .foregroundStyle(.tertiary)
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
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Button {
                            openURL(mr.webUrl)
                        } label: {
                            HStack(spacing: 8) {
                                Text("!\(mr.iid)")
                                    .fontWeight(.semibold)
                                if let author = mr.author {
                                    Text(author.shortDisplayName)
                                        .fontWeight(.semibold)
                                        .help("Auteur : \(author.fullDescription)")
                                }
                                Text("[\(projectName(for: mr))]")
                            }
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir !\(mr.iid) dans GitLab")
                        .immediateTooltip("Ouvrir !\(mr.iid) dans GitLab")
                        .accessibilityLabel(mrAccessibilityLabel(for: mr))

                        if let ticket = ticket(for: mr) {
                            Button {
                                openURL("https://fonciamillenium.atlassian.net/browse/\(ticket)")
                            } label: {
                                Text(ticket)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Ouvrir \(ticket) dans Jira")
                            .immediateTooltip("Ouvrir \(ticket) dans Jira")
                            .accessibilityLabel("Ouvrir \(ticket) dans Jira")
                        }
                    }

                    Button {
                        openURL(mr.webUrl)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
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
                    .immediateTooltip("Ouvrir !\(mr.iid) dans GitLab")
                    .accessibilityLabel(mrAccessibilityLabel(for: mr))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    refreshButton(for: mr, key: key)
                    manualPipelineActions(for: mr, key: key)
                    actionButton(for: mr)
                }
            }

            mrSignals(for: mr, key: key)
            dateRow(for: mr)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(hoveredMR == key ? Color.secondary.opacity(0.10) : .clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovering in
            hoveredMR = isHovering ? key : nil
        }
    }

    private func reviewRow(
        _ mr: MRSummary,
        statuses: [MRKey: MRApprovals],
        showsActions: Bool
    ) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Button {
                            openURL(mr.webUrl)
                        } label: {
                            HStack(spacing: 8) {
                                Text("!\(mr.iid)")
                                    .fontWeight(.semibold)
                                if let author = mr.author {
                                    Text(author.shortDisplayName)
                                        .fontWeight(.semibold)
                                        .help("Auteur : \(author.fullDescription)")
                                }
                                Text("[\(projectName(for: mr))]")
                            }
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir !\(mr.iid) dans GitLab")
                        .immediateTooltip("Ouvrir !\(mr.iid) dans GitLab")
                        .accessibilityLabel(reviewAccessibilityLabel(for: mr))

                        if let ticket = ticket(for: mr) {
                            Button {
                                openURL("https://fonciamillenium.atlassian.net/browse/\(ticket)")
                            } label: {
                                Text(ticket)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Ouvrir \(ticket) dans Jira")
                            .immediateTooltip("Ouvrir \(ticket) dans Jira")
                            .accessibilityLabel("Ouvrir \(ticket) dans Jira")
                        }
                    }

                    Button {
                        openURL(mr.webUrl)
                    } label: {
                        Text(mr.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ouvrir !\(mr.iid) dans GitLab")
                    .immediateTooltip("Ouvrir !\(mr.iid) dans GitLab")
                    .accessibilityLabel(reviewAccessibilityLabel(for: mr))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    refreshButton(for: mr, key: key)
                    manualPipelineActions(for: mr, key: key)
                    if showsActions {
                        reviewActions(for: mr, key: key, statuses: statuses)
                    }
                }
            }

            reviewSignals(for: mr, key: key, statuses: statuses)
            DateRowView(
                createdLabel: "Creee: \(ageString(mr.createdAt))",
                createdTooltip: formatDate(mr.createdAt),
                mergedLabel: nil,
                mergedTooltip: nil
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(hoveredMR == key ? Color.secondary.opacity(0.10) : .clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovering in
            hoveredMR = isHovering ? key : nil
        }
    }

    @ViewBuilder
    private func reviewSignals(
        for mr: MRSummary,
        key: MRKey,
        statuses: [MRKey: MRApprovals]
    ) -> some View {
        TagFlowLayout {
            if let ticket = ticket(for: mr),
               let jira = store.jiraStatuses[key] {
                jiraMetadata(jira, isOpen: true, ticket: ticket)
            } else if let ticket = ticket(for: mr),
                      store.jiraLoadingMRKeys.contains(key) {
                jiraLoadingMetadata(ticket: ticket)
            }

            pipelineMetadata(for: mr)

            if mr.hasConflicts {
                SemanticTag(
                    title: "Conflit",
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .critical
                )
            }

            if let behind = mr.divergedCommitsCount, behind > 0 {
                SemanticTag(
                    title: behindTagTitle(behind),
                    systemImage: "arrow.down",
                    tone: .attention
                )
            }

            if let status = statuses[key] {
                SemanticTag(
                    title: "\(status.given)/\(status.required) appro.",
                    systemImage: status.given >= status.required ? "checkmark.circle.fill" : "hand.thumbsup",
                    tone: status.given >= status.required ? .positive : .neutral
                )
                .help("\(status.given) approbation\(status.given == 1 ? "" : "s") sur \(status.required)")

                if status.isApprovedByMe {
                    SemanticTag(
                        title: "Approved",
                        systemImage: "checkmark.circle.fill",
                        tone: .positive
                    )
                    .help("Vous avez approuvé cette merge request")
                    .accessibilityLabel("Merge request approuvée")
                }

                revisitThreadsButton(for: mr, status: status)

                personalThreadButton(for: mr, status: status, key: key)

                otherThreadButton(for: mr, status: status, key: key)
            }
        }
    }

    private func reviewAccessibilityLabel(for mr: MRSummary) -> String {
        let author = mr.author.map { ", auteur \($0.fullDescription)" } ?? ""
        return "Ouvrir la merge request !\(mr.iid), \(mr.title)\(author), dans GitLab"
    }

    private func mrAccessibilityLabel(for mr: MRSummary) -> String {
        let author = mr.author.map { ", auteur \($0.fullDescription)" } ?? ""
        return "Ouvrir la merge request !\(mr.iid), \(mr.title)\(author), dans GitLab"
    }

    @ViewBuilder
    private func mrSignals(for mr: MRSummary, key: MRKey) -> some View {
        TagFlowLayout {
            if let jira = store.jiraStatuses[key] {
                jiraMetadata(jira, isOpen: mr.state == "opened", ticket: ticket(for: mr))
            } else if let ticket = ticket(for: mr),
                      store.jiraLoadingMRKeys.contains(key) {
                jiraLoadingMetadata(ticket: ticket)
            }

            stateMetadata(for: mr)
        }
    }

    @ViewBuilder
    private func revisitThreadsButton(
        for mr: MRSummary,
        status: MRApprovals
    ) -> some View {
        if status.personalThreadsNeedingRevisit > 0,
           let noteId = status.firstPersonalThreadNeedingRevisitNoteId {
            let threadCount = status.personalThreadsNeedingRevisit
            Button {
                openURL("\(mr.webUrl)#note_\(noteId)")
            } label: {
                SemanticTag(
                    title: "À revalider · \(threadCount) fil\(threadCount == 1 ? "" : "s")",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .attention
                )
            }
            .buttonStyle(.plain)
            .help("Ouvrir le premier fil personnel à revalider")
            .immediateTooltip("Ouvrir le premier fil personnel à revalider")
            .accessibilityLabel("Ouvrir le premier fil personnel à revalider dans GitLab")
        }
    }

    @ViewBuilder
    private func personalThreadButton(
        for mr: MRSummary,
        status: MRApprovals,
        key: MRKey
    ) -> some View {
        if status.myUnresolvedThreads > 0,
           let noteId = status.firstMyUnresolvedThreadNoteId {
            Button {
                openURL("\(mr.webUrl)#note_\(noteId)")
            } label: {
                SemanticTag(
                    title: "\(status.myUnresolvedThreads) mes fils",
                    systemImage: "bubble.left.fill",
                    tone: .accent
                )
                    .background(
                        hoveredPersonalThread == key ? Color.secondary.opacity(0.20) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Ouvrir votre premier fil non resolu dans GitLab")
            .immediateTooltip("Ouvrir votre premier fil non resolu dans GitLab")
            .accessibilityLabel("Ouvrir le premier de vos \(status.myUnresolvedThreads) fils non resolus dans GitLab")
            .onHover { isHovering in
                hoveredPersonalThread = isHovering ? key : nil
            }
        } else {
            SemanticTag(
                title: "\(status.myUnresolvedThreads) mes fils",
                systemImage: "bubble.left.fill",
                tone: status.myUnresolvedThreads > 0 ? .accent : .neutral
            )
                .help("\(status.myUnresolvedThreads) fil\(status.myUnresolvedThreads == 1 ? "" : "s") vous concernant non resolu\(status.myUnresolvedThreads == 1 ? "" : "s")")
        }
    }

    @ViewBuilder
    private func otherThreadButton(
        for mr: MRSummary,
        status: MRApprovals,
        key: MRKey
    ) -> some View {
        if status.otherUnresolvedThreads > 0,
           let noteId = status.firstOtherUnresolvedThreadNoteId {
            Button {
                openURL("\(mr.webUrl)#note_\(noteId)")
            } label: {
                SemanticTag(
                    title: "\(status.otherUnresolvedThreads) autres",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    tone: .attention
                )
                    .background(
                        hoveredOtherThread == key ? Color.secondary.opacity(0.20) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Ouvrir le premier fil non resolu des autres dans GitLab")
            .immediateTooltip("Ouvrir le premier fil non resolu des autres dans GitLab")
            .accessibilityLabel("Ouvrir le premier des \(status.otherUnresolvedThreads) fils non resolus des autres dans GitLab")
            .onHover { isHovering in
                hoveredOtherThread = isHovering ? key : nil
            }
        } else {
            SemanticTag(
                title: "\(status.otherUnresolvedThreads) autres",
                systemImage: "bubble.left.and.bubble.right.fill",
                tone: status.otherUnresolvedThreads > 0 ? .attention : .neutral
            )
                .help("\(status.otherUnresolvedThreads) autre\(status.otherUnresolvedThreads == 1 ? "" : "s") fil\(status.otherUnresolvedThreads == 1 ? "" : "s") non resolu\(status.otherUnresolvedThreads == 1 ? "" : "s")")
        }
    }

    @ViewBuilder
    private func reviewApprovalButton(
        for mr: MRSummary,
        key: MRKey,
        statuses: [MRKey: MRApprovals]
    ) -> some View {
        if canApproveReview(mr, key: key, statuses: statuses) {
            Button {
                confirmApproval(for: mr)
            } label: {
                Label("Approuver", systemImage: "hand.thumbsup")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isLoading)
            .help("Approuver !\(mr.iid) dans GitLab")
            .immediateTooltip("Approuver !\(mr.iid) dans GitLab")
            .accessibilityLabel("Approuver la merge request !\(mr.iid) dans GitLab")
        }
    }

    private func reviewActions(
        for mr: MRSummary,
        key: MRKey,
        statuses: [MRKey: MRApprovals]
    ) -> some View {
        HStack(spacing: 6) {
            reviewApprovalButton(for: mr, key: key, statuses: statuses)
            if store.reviewedMRs.contains(where: {
                MRKey(projectId: $0.projectId, iid: $0.iid) == key
            }) {
                Button {
                    store.hideReviewedMR(key: key)
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    hoveredReviewDismissal == key
                                        ? Color.secondary.opacity(0.18)
                                        : .clear
                                )
                        }
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
                .help("Masquer !\(mr.iid) de mes revues")
                .immediateTooltip("Masquer !\(mr.iid) de mes revues")
                .accessibilityLabel("Masquer la merge request !\(mr.iid) de mes revues")
                .onHover { isHovering in
                    hoveredReviewDismissal = isHovering ? key : nil
                    isHovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                }
            }
        }
    }

    private func refreshButton(for mr: MRSummary, key: MRKey) -> some View {
        Button {
            Task {
                await scheduler.refresh(projectId: mr.projectId, mrIid: mr.iid)
            }
        } label: {
            Group {
                if store.refreshingMRKeys.contains(key) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 16, height: 16)
            .padding(2)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .help("Actualiser !\(mr.iid)")
        .immediateTooltip("Actualiser !\(mr.iid)")
        .accessibilityLabel("Actualiser la merge request !\(mr.iid)")
        .disabled(store.refreshingMRKeys.contains(key) || !store.isConfigured)
    }

    private func canApproveReview(
        _ mr: MRSummary,
        key: MRKey,
        statuses: [MRKey: MRApprovals]
    ) -> Bool {
        guard mr.state == "opened",
              !mr.isDraft,
              store.testsAreGreen(
                  for: key,
                  pipelineId: mr.headPipeline?.id,
                  fallbackPipelineStatus: mr.headPipeline?.status
              ),
              let status = statuses[key] else {
            return false
        }
        return status.myUnresolvedThreads == 0 && !status.isApprovedByMe
    }

    @ViewBuilder
    private func manualPipelineActions(for mr: MRSummary, key: MRKey) -> some View {
        let actions = (store.manualPipelineActions[key]?.actions ?? []).filter {
            $0.kind != .autoReview || !store.isApprovedByClaude(key: key)
        }
        ForEach(actions) { action in
            if store.launchingManualPipelineJobIds.contains(action.jobId) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("\(action.kind.title) en cours")
            } else {
                Button {
                    Task {
                        await scheduler.playManualPipelineAction(
                            action,
                            projectId: mr.projectId,
                            mrIid: mr.iid
                        )
                    }
                } label: {
                    Label(action.kind.title, systemImage: action.kind.systemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("\(action.kind.title) pour !\(mr.iid)")
                .immediateTooltip("\(action.kind.title) pour !\(mr.iid)")
                .accessibilityLabel("\(action.kind.title) pour la merge request !\(mr.iid)")
            }
        }
    }

    @ViewBuilder
    private func trailingActions(for mr: MRSummary) -> some View {
        let ticketKey = ticket(for: mr)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if let jira = store.jiraStatuses[MRKey(projectId: mr.projectId, iid: mr.iid)] {
                    jiraMetadata(jira, isOpen: mr.state == "opened", ticket: ticketKey)
                } else if let ticketKey,
                          store.jiraLoadingMRKeys.contains(
                              MRKey(projectId: mr.projectId, iid: mr.iid)
                          ) {
                    jiraLoadingMetadata(ticket: ticketKey)
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
            .immediateTooltip("Retirer !\(mr.iid) de la liste")
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
            .immediateTooltip("Lancer /rebase pour !\(mr.iid) (\(behind) commits de retard)")
        }
    }

    private func metadata(for mr: MRSummary) -> some View {
        HStack(spacing: 8) {
            Text("!\(mr.iid)")
                .fontWeight(.semibold)

            Text("[\(projectName(for: mr))]")

            if let ticket = ticket(for: mr) {
                Button {
                    openURL("https://fonciamillenium.atlassian.net/browse/\(ticket)")
                } label: {
                    Text(ticket)
                }
                .buttonStyle(.plain)
            }

            stateMetadata(for: mr)
        }
        .font(.system(.callout, design: .monospaced))
        .lineLimit(1)
    }

    @ViewBuilder
    private func stateMetadata(for mr: MRSummary) -> some View {
        if mr.state != "merged" {
            if mr.isDraft {
                SemanticTag(title: "Draft", systemImage: "pencil", tone: .neutral)
            }

            pipelineMetadata(for: mr)

            if mr.hasConflicts {
                SemanticTag(
                    title: "Conflit",
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .critical
                )
            }

            if let behind = mr.divergedCommitsCount, behind > 0 {
                SemanticTag(
                    title: behindTagTitle(behind),
                    systemImage: "arrow.down",
                    tone: .attention
                )
            }

            approvalMetadata(for: mr)
        }
    }

    @ViewBuilder
    private func dateRow(for mr: MRSummary) -> some View {
        DateRowView(
            createdLabel: "Créée: \(ageString(mr.createdAt))",
            createdTooltip: formatDate(mr.createdAt),
            mergedLabel: mr.state == "merged" ? mr.mergedAt.map { "Mergée: \(ageString($0))" } : nil,
            mergedTooltip: mr.state == "merged" ? mr.mergedAt.map { formatDate($0) } : nil
        )
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

    @ViewBuilder
    private func pipelineMetadata(for mr: MRSummary) -> some View {
        switch mr.headPipeline?.status {
        case "success":
            SemanticTag(title: "CI OK", systemImage: "checkmark.circle.fill", tone: .positive)
        case "failed":
            SemanticTag(title: "CI KO", systemImage: "xmark.circle.fill", tone: .critical)
        case "running":
            SemanticTag(title: "CI en cours", systemImage: "arrow.triangle.2.circlepath", tone: .attention)
        case "pending":
            SemanticTag(title: "CI attente", systemImage: "clock.fill", tone: .attention)
        case "canceled":
            SemanticTag(title: "CI annulée", systemImage: "minus.circle.fill", tone: .neutral)
        case .some:
            SemanticTag(title: "CI ?", systemImage: "questionmark.circle", tone: .neutral)
        case .none:
            SemanticTag(title: "CI n/a", systemImage: "minus", tone: .neutral)
        }
    }

    @ViewBuilder
    private func approvalMetadata(for mr: MRSummary) -> some View {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        if let approval = store.approvals[key] {
            SemanticTag(
                title: "\(approval.given)/\(approval.required) appro.",
                systemImage: approval.given >= approval.required ? "checkmark.circle.fill" : "hand.thumbsup.fill",
                tone: approval.given >= approval.required ? .positive : .neutral
            )

            if approval.unresolvedThreads > 0 {
                SemanticTag(
                    title: "\(approval.unresolvedThreads) fil\(approval.unresolvedThreads == 1 ? "" : "s")",
                    systemImage: "bubble.left.fill",
                    tone: .attention
                )
            }
        }
    }

    @ViewBuilder
    private func jiraMetadata(_ jira: JiraIssueStatus, isOpen: Bool, ticket: String?) -> some View {
        if let ticket {
            Button {
                openURL("https://fonciamillenium.atlassian.net/browse/\(ticket)")
            } label: {
                SemanticTag(
                    title: jira.name,
                    systemImage: jiraSymbol(jira, isOpen: isOpen),
                    tone: jiraTone(jira, isOpen: isOpen)
                )
            }
            .buttonStyle(.plain)
            .help("Ouvrir \(ticket) dans Jira")
            .immediateTooltip("Ouvrir \(ticket) dans Jira")
        } else {
            SemanticTag(
                title: jira.name,
                systemImage: jiraSymbol(jira, isOpen: isOpen),
                tone: jiraTone(jira, isOpen: isOpen)
            )
        }
    }

    @ViewBuilder
    private func jiraLoadingMetadata(ticket: String) -> some View {
        Button {
            openURL("https://fonciamillenium.atlassian.net/browse/\(ticket)")
        } label: {
            SemanticTag(title: "Jira...", systemImage: "ticket", tone: .neutral)
        }
        .buttonStyle(.plain)
        .help("Ouvrir \(ticket) dans Jira")
        .immediateTooltip("Ouvrir \(ticket) dans Jira")
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

    private func isToReview(_ mr: MRSummary) -> Bool {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        guard let status = store.jiraStatuses[key]?.name else { return false }
        return ["to review", "code review"].contains(
            status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
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

    private func jiraTone(_ jira: JiraIssueStatus, isOpen: Bool) -> SemanticTagTone {
        jiraTagTone(
            name: jira.name,
            categoryKey: jira.categoryKey,
            isOpen: isOpen,
            isStale: jira.isStale
        )
    }

    private func intervalDescription(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            "Jamais"
        case 3_600:
            "1 h"
        case 14_400:
            "4 h"
        case 28_800:
            "8 h"
        case 86_400:
            "24 h"
        default:
            seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
        }
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

    private func confirmApproval(for mr: MRSummary) {
        let alert = NSAlert()
        alert.messageText = "Approuver la merge request ?"
        alert.informativeText = "Cette action envoie votre approbation pour !\(mr.iid) dans GitLab."
        alert.addButton(withTitle: "Approuver")
        alert.addButton(withTitle: "Annuler")
        alert.alertStyle = .informational
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                try await scheduler.approve(projectId: mr.projectId, mrIid: mr.iid)
                await scheduler.refresh(projectId: mr.projectId, mrIid: mr.iid)
            } catch {
                store.lastError = "Approbation !\(mr.iid) : \(error.localizedDescription)"
                NotificationService.shared.notify(
                    identifier: "review-approval-\(mr.projectId)-\(mr.iid)",
                    title: "Approbation echouee - !\(mr.iid)",
                    body: error.localizedDescription,
                    url: mr.webUrl
                )
            }
        }
    }
}

private struct DateLabelView: View {
    let label: String
    let tooltip: String

    @State private var isHovered = false

    var body: some View {
        Text(label)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .overlay(alignment: .top) {
                if isHovered {
                    Text(tooltip)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 2)
                        .offset(y: -28)
                        .allowsHitTesting(false)
                        .fixedSize()
                }
            }
    }
}

private struct DateRowView: View {
    let createdLabel: String
    let createdTooltip: String
    let mergedLabel: String?
    let mergedTooltip: String?

    var body: some View {
        HStack(spacing: 12) {
            if let mergedLabel, let mergedTooltip {
                DateLabelView(label: mergedLabel, tooltip: mergedTooltip)
            }
            DateLabelView(label: createdLabel, tooltip: createdTooltip)
        }
        .font(.system(.callout, design: .monospaced))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
}
