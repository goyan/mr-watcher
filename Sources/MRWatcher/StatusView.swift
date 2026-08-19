import AppKit
import SwiftUI

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
    // Non persistées : retour à `.all` à chaque lancement (plan D2).
    @State private var myReviewsChip: ReviewChip = .all
    @State private var reviewableChip: ReviewChip = .all

    private static let myReviewsChips: [ReviewChip] = [.all, .needsRevisit, .myThreads, .approved]
    private static let reviewableChips: [ReviewChip] = [.all, .needsRevisit, .myThreads, .noReview, .toReview]

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

    private var mrLookup: [MRKey: MRSummary] {
        lookup(from: store.mrs)
    }

    private func lookup(from mrs: [MRSummary]) -> [MRKey: MRSummary] {
        Dictionary(
            mrs.map { (MRKey(projectId: $0.projectId, iid: $0.iid), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Filtre l'auto review masquée si Claude a déjà approuvé — même prédicat que
    /// l'ancien `manualPipelineActions(for:key:)`, calculé une fois pour toutes les lignes.
    private var manualActionsByKey: [MRKey: [ManualPipelineAction]] {
        Dictionary(uniqueKeysWithValues: store.manualPipelineActions.map { key, value in
            (key, value.actions.filter { $0.kind != .autoReview || !store.isApprovedByClaude(key: key) })
        })
    }

    private var reviewableToReviewCount: Int {
        store.reviewableMRs.filter(isToReview).count
    }

    private var reviewableOtherCount: Int {
        store.reviewableMRs.count - reviewableToReviewCount
    }

    /// Compteur de pied de page « à revalider » — réutilise le prédicat de chip
    /// (`StatusPresentation.swift`), jamais réimplémenté ici.
    private func needsRevisitCount(mrs: [MRSummary], statuses: [MRKey: MRApprovals]) -> Int {
        chipCounts(for: [.needsRevisit], mrs: mrs, approvals: statuses, jiraStatuses: store.jiraStatuses)[.needsRevisit] ?? 0
    }

    /// Condition d'affichage de `jiraConfigWarning` : au moins un ticket détecté
    /// quelque part dans l'app. L'en-tête est partagé par les trois onglets, donc on
    /// regarde les trois sources plutôt que la seule liste active — sinon le bandeau
    /// apparaîtrait/disparaîtrait au changement d'onglet pour un même réglage.
    private var hasAnyDetectedTicket: Bool {
        let ticketPrefix = ConfigManager.shared.ticketPrefix
        return (store.mrs + store.reviewedMRs + store.reviewableMRs)
            .contains { detectedTicket(in: $0, prefix: ticketPrefix) != nil }
    }

    private var appVersion: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !version.isEmpty else {
            return "Version indisponible"
        }
        return "v\(version)"
    }

    /// Le survol doit dire ce que fera le clic, dans les deux états — sinon le tooltip
    /// ment autant que l'ancien `Text` inerte qu'il remplaçait.
    private var versionTooltip: String {
        if updaterController.updateAvailable {
            "Mise à jour disponible — cliquer pour installer\n\n\(ReleaseNotes.summary)"
        } else {
            "Rechercher les mises à jour\n\n\(ReleaseNotes.summary)"
        }
    }

    private var versionAccessibilityLabel: String {
        if updaterController.updateAvailable {
            "Version \(appVersion). Mise à jour disponible. Cliquer pour installer."
        } else {
            "Version \(appVersion). \(ReleaseNotes.summary) Cliquer pour rechercher les mises à jour."
        }
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
            // Dérivée du budget réel des colonnes (bug §1 étape 4) — ne pas recoder un
            // nombre magique ici : voir `DesignTokens.tableMinWidth`.
            minWidth: DesignTokens.tableMinWidth,
            idealWidth: 1_140,
            maxWidth: .infinity,
            minHeight: 600,
            idealHeight: 700,
            maxHeight: .infinity
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("MR Watcher", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            syncStatus

            jiraWarning

            jiraConfigWarning

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

    /// Réservé aux utilisateurs qui avaient un lien Jira codé en dur avant que l'URL
    /// devienne configurable (dé-hardcoding de l'employeur, cf. `jiraBaseURL`) : sans
    /// ce bandeau, un ticket devient gris et non cliquable sans aucune explication à
    /// l'écran — les notes de version ne suffisent pas, personne ne les lit.
    @ViewBuilder
    private var jiraConfigWarning: some View {
        if ConfigManager.shared.jiraBaseURL.isEmpty && hasAnyDetectedTicket {
            Button {
                setupController.open(store: store, scheduler: scheduler)
            } label: {
                Label("URL Jira non configurée", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(Self.jiraConfigWarningTooltip)
            .immediateTooltip(Self.jiraConfigWarningTooltip)
            .accessibilityLabel(
                "URL Jira non configurée. \(Self.jiraConfigWarningTooltip) Cliquer pour ouvrir les réglages."
            )
        }
    }

    private static let jiraConfigWarningTooltip =
        "Les tickets ne sont pas cliquables tant que l'URL de votre instance Jira n'est pas renseignée. Réglages → Jira."

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
            let now = Date()
            let lookup = mrLookup
            let ticketPrefix = ConfigManager.shared.ticketPrefix
            ScrollView {
                StatusTableView(
                    layout: .author,
                    openRows: buildRows(
                        mrs: store.mrs,
                        approvals: store.approvals,
                        jiraStatuses: store.jiraStatuses,
                        jiraLoadingKeys: store.jiraLoadingMRKeys,
                        testsAreGreen: { key in
                            guard let mr = lookup[key] else { return false }
                            return store.testsAreGreen(
                                for: key,
                                pipelineId: mr.headPipeline?.id,
                                fallbackPipelineStatus: mr.headPipeline?.status
                            )
                        },
                        context: .author,
                        ticketPrefix: ticketPrefix,
                        now: now
                    ),
                    mergedRows: buildMergedRows(
                        mrs: store.mrs,
                        jiraStatuses: store.jiraStatuses,
                        ticketPrefix: ticketPrefix,
                        now: now
                    ),
                    mrLookup: lookup,
                    jiraBaseURL: ConfigManager.shared.jiraBaseURL,
                    refreshingKeys: store.refreshingMRKeys,
                    manualActions: manualActionsByKey,
                    launchingJobIds: store.launchingManualPipelineJobIds,
                    callbacks: StatusTableCallbacks(
                        openURL: openURL,
                        refresh: { key in
                            Task { await scheduler.refresh(projectId: key.projectId, mrIid: key.iid) }
                        },
                        playAction: { key, action in
                            Task {
                                await scheduler.playManualPipelineAction(
                                    action,
                                    projectId: key.projectId,
                                    mrIid: key.iid
                                )
                            }
                        },
                        rebase: { mr in confirmRebase(for: mr) },
                        dismissMerged: { key in store.dismiss(key: key) },
                        approve: nil,
                        dismissReview: nil
                    )
                )
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
            reviewerTable(
                mrs: store.reviewedMRs,
                statuses: store.reviewStatuses,
                chips: Self.myReviewsChips,
                selection: $myReviewsChip,
                showsDismiss: true
            )
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
            reviewerTable(
                mrs: store.reviewableMRs,
                statuses: store.reviewableStatuses,
                chips: Self.reviewableChips,
                selection: $reviewableChip,
                showsDismiss: false
            )
        }
    }

    /// Table reviewer partagée entre « Mes revues » et « À revoir » — seuls la source
    /// de données, les chips et `showsDismiss` diffèrent. Le piège de cette étape :
    /// `lookup`/`testsAreGreen` doivent puiser dans `mrs` (donc `store.reviewedMRs` ou
    /// `store.reviewableMRs`), jamais dans `store.mrs` — une MR reviewée n'y est pas
    /// forcément (on ne l'a pas forcément soi-même ouverte).
    @ViewBuilder
    private func reviewerTable(
        mrs: [MRSummary],
        statuses: [MRKey: MRApprovals],
        chips: [ReviewChip],
        selection: Binding<ReviewChip>,
        showsDismiss: Bool
    ) -> some View {
        let now = Date()
        let rowLookup = lookup(from: mrs)
        let ticketPrefix = ConfigManager.shared.ticketPrefix
        let filteredMRs = mrs.filter { mr in
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            return matchesChip(selection.wrappedValue, approvals: statuses[key], jiraStatus: store.jiraStatuses[key])
        }
        let counts = chipCounts(for: chips, mrs: mrs, approvals: statuses, jiraStatuses: store.jiraStatuses)

        VStack(spacing: 0) {
            FilterChipsView(chips: chips, counts: counts, selection: selection)
            Divider()
            ScrollView {
                StatusTableView(
                    layout: .reviewer(showsDismiss: showsDismiss),
                    openRows: buildRows(
                        mrs: filteredMRs,
                        approvals: statuses,
                        jiraStatuses: store.jiraStatuses,
                        jiraLoadingKeys: store.jiraLoadingMRKeys,
                        testsAreGreen: { key in
                            guard let mr = rowLookup[key] else { return false }
                            return store.testsAreGreen(
                                for: key,
                                pipelineId: mr.headPipeline?.id,
                                fallbackPipelineStatus: mr.headPipeline?.status
                            )
                        },
                        context: .reviewer,
                        ticketPrefix: ticketPrefix,
                        now: now
                    ),
                    mergedRows: [],
                    mrLookup: rowLookup,
                    jiraBaseURL: ConfigManager.shared.jiraBaseURL,
                    refreshingKeys: store.refreshingMRKeys,
                    manualActions: manualActionsByKey,
                    launchingJobIds: store.launchingManualPipelineJobIds,
                    callbacks: StatusTableCallbacks(
                        openURL: openURL,
                        refresh: { key in
                            Task { await scheduler.refresh(projectId: key.projectId, mrIid: key.iid) }
                        },
                        playAction: { key, action in
                            Task {
                                await scheduler.playManualPipelineAction(
                                    action,
                                    projectId: key.projectId,
                                    mrIid: key.iid
                                )
                            }
                        },
                        rebase: nil,
                        dismissMerged: nil,
                        approve: { mr in confirmApproval(for: mr) },
                        dismissReview: showsDismiss ? { key in store.hideReviewedMR(key: key) } : nil
                    )
                )
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
                // Text(verbatim:) partout ci-dessous : un Int interpolé dans un Text("...")
                // littéral construit une LocalizedStringKey, qui applique le séparateur de
                // milliers français (le bug déjà payé sur !IID — plan §9.3a). Ces compteurs
                // restent petits aujourd'hui, mais on ferme la classe plutôt que de la
                // laisser se réarmer dans un pied de page qu'on relira moins souvent.
                if contentTab == .myMRs {
                    Text(verbatim: "\(openedMRs.count) ouverte\(openedMRs.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    if !mergedMRs.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(verbatim: "\(mergedMRs.count) mergée\(mergedMRs.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                } else if contentTab == .myReviews {
                    Text(verbatim: "\(store.reviewedMRs.count) revue\(store.reviewedMRs.count == 1 ? "" : "s") en cours")
                        .foregroundStyle(.secondary)
                    let revisit = needsRevisitCount(mrs: store.reviewedMRs, statuses: store.reviewStatuses)
                    if revisit > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(verbatim: "\(revisit) à revalider")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(verbatim: "\(store.reviewableMRs.count) MR\(store.reviewableMRs.count == 1 ? "" : "s") à revoir")
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(verbatim: "\(reviewableToReviewCount) To Review")
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(verbatim: "\(reviewableOtherCount) Les autres")
                        .foregroundStyle(.secondary)
                    let revisit = needsRevisitCount(mrs: store.reviewableMRs, statuses: store.reviewableStatuses)
                    if revisit > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(verbatim: "\(revisit) à revalider")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Toujours cliquable, même sans mise à jour connue : cet élément réagit déjà
            // au survol (notes de version), un contrôle qui répond au survol et ignore le
            // clic est un mensonge d'interface — même raisonnement que le tag Jira non
            // cliquable quand l'URL est vide. Seule la pastille orange reste conditionnée
            // à `updateAvailable` : elle signale une mise à jour, pas la cliquabilité.
            Button {
                updaterController.checkForUpdates()
            } label: {
                HStack(spacing: 4) {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                    if updaterController.updateAvailable {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .help(versionTooltip)
            .immediateTooltip(versionTooltip)
            .accessibilityLabel(versionAccessibilityLabel)
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

    private func isToReview(_ mr: MRSummary) -> Bool {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
        guard let status = store.jiraStatuses[key]?.name else { return false }
        return ["to review", "code review"].contains(
            status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                    title: "Approbation échouée — !\(mr.iid)",
                    body: error.localizedDescription,
                    url: mr.webUrl
                )
            }
        }
    }
}

