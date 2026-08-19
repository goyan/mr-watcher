import Foundation
import Observation

struct MRKey: Hashable, Codable {
    let projectId: Int
    let iid: Int
}

struct ManualPipelineActions {
    let pipelineId: Int
    let actions: [ManualPipelineAction]
    let buildAffectedStatus: String?
}

private enum ManualPipelineActionsLoadState {
    case loading(pipelineId: Int)
    case failed(pipelineId: Int)
    case loaded(ManualPipelineActions)

    var pipelineId: Int {
        switch self {
        case let .loading(pipelineId), let .failed(pipelineId):
            pipelineId
        case let .loaded(actions):
            actions.pipelineId
        }
    }
}

struct WatchEvent: Identifiable {
    let id: UUID
    let kind: WatchEventKind
    let mrTitle: String
    let webUrl: String
    let mrIid: Int
    let createdAt: Date
}

enum WatchEventKind {
    case ciFailure, ciSuccess, newComment, merged, newApproval, mrReady
}

@MainActor
@Observable
final class StateStore {
    var mrs: [MRSummary] = []
    var approvals: [MRKey: MRApprovals] = [:]
    var reviewedMRs: [MRSummary] = []
    var reviewStatuses: [MRKey: MRApprovals] = [:]
    var reviewableMRs: [MRSummary] = []
    var reviewableStatuses: [MRKey: MRApprovals] = [:]
    var events: [WatchEvent] = []
    var isLoading: Bool = false
    var lastError: String? = nil
    var lastErrorIsAuth: Bool = false
    var jiraError: String? = nil
    var lastSuccessfulPollAt: Date? = nil
    var dismissedKeys: Set<MRKey> = []
    var jiraStatuses: [MRKey: JiraIssueStatus] = [:]
    var refreshingMRKeys: Set<MRKey> = []
    var manualPipelineActions: [MRKey: ManualPipelineActions] = [:]
    var launchingManualPipelineJobIds: Set<Int> = []

    var isConfigured: Bool = ConfigManager.shared.isConfigured

    private let maxEvents = 50
    private var seenEventKeys: Set<String> = []
    private static let persistedMergedStateKey = "persistedMergedMRState"
    private static let persistedReviewedMRKeysKey = "persistedReviewedMRKeys"
    private static let dismissedReviewedMRKeysKey = "dismissedReviewedMRKeys"
    private var persistedReviewedMRKeys: Set<MRKey>
    private var dismissedReviewedMRKeys: Set<MRKey>
    private var manualPipelineActionLoads: [MRKey: (pipelineId: Int, token: UUID)] = [:]
    private var manualPipelineActionLoadStates: [MRKey: ManualPipelineActionsLoadState] = [:]

    private struct PersistedMergedState: Codable {
        let mergedMRs: [MRSummary]
        let dismissedKeys: [MRKey]
    }

    init() {
        let persistedState = Self.loadPersistedMergedState()
        mrs = persistedState.mergedMRs
        dismissedKeys = Set(persistedState.dismissedKeys)
        persistedReviewedMRKeys = Self.loadPersistedReviewedMRKeys()
        dismissedReviewedMRKeys = Self.loadDismissedReviewedMRKeys()
    }

    private func eventKey(projectId: Int, iid: Int, kind: WatchEventKind) -> String {
        let kindStr: String = switch kind {
        case .ciFailure: "ciFailure"
        case .ciSuccess: "ciSuccess"
        case .newComment: "newComment"
        case .merged: "merged"
        case .newApproval: "newApproval"
        case .mrReady: "mrReady"
        }
        return "\(projectId)-\(iid)-\(kindStr)"
    }

    func dismiss(key: MRKey) {
        dismissedKeys.insert(key)
        mrs.removeAll { MRKey(projectId: $0.projectId, iid: $0.iid) == key }
        jiraStatuses[key] = nil
        discardStaleManualPipelineActions()
        persistMergedState()
    }

    func currentReviewedMRKeys() -> Set<MRKey> {
        persistedReviewedMRKeys
    }

    func currentDismissedReviewedMRKeys() -> Set<MRKey> {
        dismissedReviewedMRKeys
    }

    func replaceReviewedMRKeys(_ keys: Set<MRKey>) {
        persistedReviewedMRKeys = keys.subtracting(dismissedReviewedMRKeys)
        persistReviewedMRKeys()
    }

    func updateReviewedMRs(
        _ mrs: [MRSummary],
        statuses: [MRKey: MRApprovals]
    ) {
        reviewedMRs = mrs.filter {
            !dismissedReviewedMRKeys.contains(
                MRKey(projectId: $0.projectId, iid: $0.iid)
            )
        }
        reviewStatuses = statuses.filter { !dismissedReviewedMRKeys.contains($0.key) }
        discardStaleManualPipelineActions()
    }

    func updateReviewableMRs(
        _ mrs: [MRSummary],
        statuses: [MRKey: MRApprovals]
    ) {
        reviewableMRs = mrs
        let keys = Set(mrs.map { MRKey(projectId: $0.projectId, iid: $0.iid) })
        reviewableStatuses = statuses.filter { keys.contains($0.key) }
        discardStaleManualPipelineActions()
    }

    func hideReviewedMR(key: MRKey) {
        dismissedReviewedMRKeys.insert(key)
        persistedReviewedMRKeys.remove(key)
        reviewedMRs.removeAll { MRKey(projectId: $0.projectId, iid: $0.iid) == key }
        reviewStatuses[key] = nil
        jiraStatuses[key] = nil
        discardStaleManualPipelineActions()
        persistReviewedMRKeys()
        persistDismissedReviewedMRKeys()
    }

    func updateRefreshedMR(_ mr: MRSummary, approvals approval: MRApprovals) {
        let key = MRKey(projectId: mr.projectId, iid: mr.iid)

        mrs = mrs.map {
            MRKey(projectId: $0.projectId, iid: $0.iid) == key ? mr : $0
        }
        reviewedMRs = reviewedMRs.map {
            MRKey(projectId: $0.projectId, iid: $0.iid) == key ? mr : $0
        }
        reviewableMRs = reviewableMRs.map {
            MRKey(projectId: $0.projectId, iid: $0.iid) == key ? mr : $0
        }

        if mrs.contains(where: { MRKey(projectId: $0.projectId, iid: $0.iid) == key }) {
            approvals[key] = approval
        }
        if reviewedMRs.contains(where: { MRKey(projectId: $0.projectId, iid: $0.iid) == key }) {
            reviewStatuses[key] = approval
        }
        if reviewableMRs.contains(where: { MRKey(projectId: $0.projectId, iid: $0.iid) == key }) {
            reviewableStatuses[key] = approval
        }
        invalidateManualPipelineActions(for: [key])
        discardStaleManualPipelineActions()
        persistMergedState()
    }

    func beginManualPipelineActionsLoad(
        for key: MRKey,
        pipelineId: Int
    ) -> UUID? {
        guard currentDisplayedMR(for: key)?.headPipeline?.id == pipelineId else {
            return nil
        }
        let token = UUID()
        manualPipelineActionLoads[key] = (pipelineId, token)
        manualPipelineActionLoadStates[key] = .loading(pipelineId: pipelineId)
        return token
    }

    func updateManualPipelineActions(
        _ result: PipelineJobActions,
        for key: MRKey,
        pipelineId: Int,
        token: UUID
    ) {
        guard let load = manualPipelineActionLoads[key],
              load.pipelineId == pipelineId,
              load.token == token,
              currentDisplayedMR(for: key)?.headPipeline?.id == pipelineId else {
            return
        }
        let actions = ManualPipelineActions(
            pipelineId: pipelineId,
            actions: result.actions,
            buildAffectedStatus: result.buildAffectedStatus
        )
        manualPipelineActions[key] = actions
        manualPipelineActionLoadStates[key] = .loaded(actions)
    }

    func failManualPipelineActionsLoad(
        for key: MRKey,
        pipelineId: Int,
        token: UUID
    ) {
        guard let load = manualPipelineActionLoads[key],
              load.pipelineId == pipelineId,
              load.token == token,
              currentDisplayedMR(for: key)?.headPipeline?.id == pipelineId else {
            return
        }
        manualPipelineActions[key] = nil
        manualPipelineActionLoadStates[key] = .failed(pipelineId: pipelineId)
    }

    func testsAreGreen(
        for key: MRKey,
        pipelineId: Int?,
        fallbackPipelineStatus: String?
    ) -> Bool {
        guard let pipelineId,
              case let .loaded(actions)? = manualPipelineActionLoadStates[key],
              actions.pipelineId == pipelineId else {
            return false
        }
        guard let buildAffectedStatus = actions.buildAffectedStatus else {
            return fallbackPipelineStatus?.lowercased() == "success"
        }
        return buildAffectedStatus == "success"
    }

    func invalidateManualPipelineActions(for keys: some Sequence<MRKey>) {
        for key in keys {
            manualPipelineActions[key] = nil
            manualPipelineActionLoads[key] = nil
            manualPipelineActionLoadStates[key] = nil
        }
    }

    func isApprovedByClaude(key: MRKey) -> Bool {
        approvals[key]?.isApprovedByClaude == true
            || reviewStatuses[key]?.isApprovedByClaude == true
            || reviewableStatuses[key]?.isApprovedByClaude == true
    }

    func isDisplayingMR(key: MRKey) -> Bool {
        currentDisplayedMR(for: key) != nil
    }

    func update(
        mrs: [MRSummary],
        mergedMRs: [MRSummary] = [],
        approvals: [MRKey: MRApprovals],
        notifyAboutMerges: Bool = true
    ) {
        var newEvents: [WatchEvent] = []

        // Detect merges: MRs that disappeared from the opened list and were confirmed merged
        if notifyAboutMerges {
            for mr in mergedMRs {
                let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                guard !dismissedKeys.contains(key) else { continue }
                let ek = eventKey(projectId: mr.projectId, iid: mr.iid, kind: .merged)
                guard !seenEventKeys.contains(ek) else { continue }
                seenEventKeys.insert(ek)
                newEvents.append(WatchEvent(
                    id: UUID(), kind: .merged,
                    mrTitle: mr.title, webUrl: mr.webUrl, mrIid: mr.iid, createdAt: Date()
                ))
            }
        }

        // CI change and comment notifications (only for opened MRs)
        for mr in mrs {
            let prevMR = self.mrs.first { $0.iid == mr.iid && $0.projectId == mr.projectId }

            // CI change notification (only for opened MRs)
            if mr.state == "opened",
               let prev = prevMR,
               let prevStatus = prev.headPipeline?.status,
               let currStatus = mr.headPipeline?.status,
               prevStatus != currStatus {
                let kind: WatchEventKind? = switch currStatus {
                case "failed": .ciFailure
                case "success": .ciSuccess
                default: nil
                }
                if let kind {
                    // prevStatus != currStatus is already a natural guard; no seenEventKeys needed.
                    newEvents.append(WatchEvent(
                        id: UUID(), kind: kind,
                        mrTitle: mr.title,
                        webUrl: mr.headPipeline?.webUrl ?? mr.webUrl,
                        mrIid: mr.iid, createdAt: Date()
                    ))
                }
            }

            // New comment notification (only for opened MRs)
            // notesCount > prev.notesCount is already a natural guard; no seenEventKeys needed.
            if mr.state == "opened", let prev = prevMR, mr.notesCount > prev.notesCount {
                newEvents.append(WatchEvent(
                    id: UUID(), kind: .newComment,
                    mrTitle: mr.title, webUrl: mr.webUrl, mrIid: mr.iid, createdAt: Date()
                ))
            }

            // New approval notification
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            if !dismissedKeys.contains(key),
               let prevAppr = self.approvals[key], let currAppr = approvals[key],
               currAppr.given > prevAppr.given {
                newEvents.append(WatchEvent(
                    id: UUID(), kind: .newApproval,
                    mrTitle: mr.title, webUrl: mr.webUrl, mrIid: mr.iid, createdAt: Date()
                ))
            }

            // MR ready (draft → non-draft)
            if let prev = prevMR, prev.isDraft, !mr.isDraft {
                newEvents.append(WatchEvent(
                    id: UUID(), kind: .mrReady,
                    mrTitle: mr.title, webUrl: mr.webUrl, mrIid: mr.iid, createdAt: Date()
                ))
            }
        }

        for event in newEvents {
            let body: String = switch event.kind {
            case .ciFailure: "Pipeline échoué"
            case .ciSuccess: "Pipeline réussi"
            case .newComment: "Nouveau commentaire"
            case .merged: event.mrTitle
            case .newApproval: "La MR a été approuvée."
            case .mrReady: "La MR n'est plus en draft."
            }
            let title: String = switch event.kind {
            case .merged: "MR mergée 🎉"
            case .newApproval: "Approbation reçue — !\(event.mrIid)"
            case .mrReady: "MR prête — !\(event.mrIid)"
            default: event.mrTitle
            }
            let notifId = event.webUrl.replacingOccurrences(of: "/", with: "-") + "-\(event.kind)"
            NotificationService.shared.notify(identifier: notifId, title: title, body: body, url: event.webUrl)
        }

        // New merged MRs confirmed this poll (non-dismissed)
        let newMergedFiltered = mergedMRs.filter { !dismissedKeys.contains(MRKey(projectId: $0.projectId, iid: $0.iid)) }
        let newMergedKeys = Set(newMergedFiltered.map { MRKey(projectId: $0.projectId, iid: $0.iid) })

        // Previously merged MRs retained in memory (non-dismissed, not replaced by newly detected)
        let previousMerged = self.mrs.filter {
            $0.state == "merged" && !dismissedKeys.contains(MRKey(projectId: $0.projectId, iid: $0.iid))
        }
        let retainedPreviousMerged = previousMerged.filter { !newMergedKeys.contains(MRKey(projectId: $0.projectId, iid: $0.iid)) }

        // Opened MRs from API (closed ones are silently dropped; filter dismissed)
        let openedFiltered = mrs.filter {
            $0.state != "closed" && !dismissedKeys.contains(MRKey(projectId: $0.projectId, iid: $0.iid))
        }

        self.mrs = openedFiltered + newMergedFiltered + retainedPreviousMerged
        self.approvals = approvals
        discardStaleManualPipelineActions()
        self.events = Array((newEvents + self.events).prefix(maxEvents))
        persistMergedState()
    }

    func clearEvents() {
        events = []
        // seenEventKeys is intentionally NOT cleared: it is a dedup memory,
        // not a display cache. Clearing it would cause re-notifications on the next poll.
    }

    private func persistMergedState() {
        let mergedMRs = mrs.filter { $0.state == "merged" }
        let state = PersistedMergedState(
            mergedMRs: mergedMRs,
            dismissedKeys: Array(dismissedKeys)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedMergedStateKey)
    }

    private func currentDisplayedMR(for key: MRKey) -> MRSummary? {
        (mrs + reviewedMRs + reviewableMRs).first {
            MRKey(projectId: $0.projectId, iid: $0.iid) == key
        }
    }

    private func discardStaleManualPipelineActions() {
        manualPipelineActions = manualPipelineActions.filter { key, value in
            currentDisplayedMR(for: key)?.headPipeline?.id == value.pipelineId
        }
        manualPipelineActionLoads = manualPipelineActionLoads.filter { key, value in
            currentDisplayedMR(for: key)?.headPipeline?.id == value.pipelineId
        }
        manualPipelineActionLoadStates = manualPipelineActionLoadStates.filter { key, value in
            currentDisplayedMR(for: key)?.headPipeline?.id == value.pipelineId
        }
    }

    private static func loadPersistedMergedState() -> PersistedMergedState {
        guard let data = UserDefaults.standard.data(forKey: persistedMergedStateKey) else {
            return PersistedMergedState(mergedMRs: [], dismissedKeys: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PersistedMergedState.self, from: data))
            ?? PersistedMergedState(mergedMRs: [], dismissedKeys: [])
    }

    private func persistReviewedMRKeys() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(Array(persistedReviewedMRKeys)) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedReviewedMRKeysKey)
    }

    private static func loadPersistedReviewedMRKeys() -> Set<MRKey> {
        guard let data = UserDefaults.standard.data(forKey: persistedReviewedMRKeysKey),
              let keys = try? JSONDecoder().decode([MRKey].self, from: data) else {
            return []
        }
        return Set(keys)
    }

    private func persistDismissedReviewedMRKeys() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(Array(dismissedReviewedMRKeys)) else { return }
        UserDefaults.standard.set(data, forKey: Self.dismissedReviewedMRKeysKey)
    }

    private static func loadDismissedReviewedMRKeys() -> Set<MRKey> {
        guard let data = UserDefaults.standard.data(forKey: dismissedReviewedMRKeysKey),
              let keys = try? JSONDecoder().decode([MRKey].self, from: data) else {
            return []
        }
        return Set(keys)
    }
}
