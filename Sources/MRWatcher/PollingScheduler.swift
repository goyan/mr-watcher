import Foundation

@MainActor
final class PollingScheduler {
    private let store: StateStore
    private let gitlab: GitLabService
    private let jira: JiraService
    private var task: Task<Void, Never>?
    private var manualPipelineActionsTask: Task<Void, Never>?
    private var shouldBootstrapRecentlyMergedMRs = true
    private var shouldBootstrapReviewedMRs = true
    private var reviewedRefreshCursor = 0
    private static var latestJiraPublicationToken = UUID()

    // Bootstrap samples recent comment history without unbounded periodic scans.
    private static let reviewedEventsBootstrapPageLimit = 3
    private static let reviewedEventsPollingPageLimit = 1
    private static let reviewedMRDetailLimit = 50
    private static let newlyDiscoveredReviewDetailLimit = 10
    private static let manualPipelineActionMRLimit = 30
    private static let manualPipelineActionConcurrencyLimit = 4

    private struct PollResult {
        let reviewedRefreshCursor: Int
    }

    private var intervalSeconds: Int? {
        guard let storedInterval = UserDefaults.standard.object(
            forKey: "pollIntervalSeconds"
        ) as? Int else {
            return 600
        }
        return storedInterval == 0 ? nil : max(15, storedInterval)
    }

    init(store: StateStore, gitlab: GitLabService, jira: JiraService) {
        self.store = store
        self.gitlab = gitlab
        self.jira = jira
    }

    func start() {
        stop()
        task = Task { [weak self, store, gitlab, jira] in
            while !Task.isCancelled {
                guard let self else { return }
                let pollState = await MainActor.run {
                    (self.shouldBootstrapRecentlyMergedMRs,
                     self.shouldBootstrapReviewedMRs,
                     self.reviewedRefreshCursor)
                }
                let result = await self.poll(
                    store: store,
                    gitlab: gitlab,
                    jira: jira,
                    shouldBootstrapRecentlyMergedMRs: pollState.0,
                    shouldBootstrapReviewedMRs: pollState.1,
                    reviewedRefreshCursor: pollState.2
                )
                if let result {
                    await MainActor.run {
                        self.shouldBootstrapRecentlyMergedMRs = false
                        self.shouldBootstrapReviewedMRs = false
                        self.reviewedRefreshCursor = result.reviewedRefreshCursor
                    }
                }
                guard let intervalSeconds = await MainActor.run(body: {
                    self.intervalSeconds
                }) else {
                    return
                }
                try? await Task.sleep(for: .seconds(Double(intervalSeconds)))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        manualPipelineActionsTask?.cancel()
        manualPipelineActionsTask = nil
    }

    func restart() {
        if intervalSeconds == nil {
            stop()
        } else {
            start()
        }
    }

    func rebase(projectId: Int, mrIid: Int) async throws {
        try await gitlab.rebase(projectId: projectId, mrIid: mrIid)
    }

    func approve(projectId: Int, mrIid: Int) async throws {
        try await gitlab.approve(projectId: projectId, mrIid: mrIid)
    }

    func refresh(projectId: Int, mrIid: Int) async {
        let key = MRKey(projectId: projectId, iid: mrIid)
        guard !store.refreshingMRKeys.contains(key) else { return }
        store.refreshingMRKeys.insert(key)
        store.invalidateManualPipelineActions(for: [key])
        defer { store.refreshingMRKeys.remove(key) }

        do {
            let detail = try await gitlab.fetchMRDetail(projectId: projectId, mrIid: mrIid)
            async let approvals = gitlab.fetchApprovals(projectId: projectId, mrIid: mrIid)
            store.updateRefreshedMR(
                detail,
                approvals: try await approvals
            )
            store.lastError = nil
            store.lastErrorIsAuth = false

            scheduleManualPipelineActions(for: [key: detail])
            Task { [weak self] in
                guard let self else { return }
                await self.refreshJiraStatus(for: key)
            }
        } catch {
            store.lastError = "Actualisation !\(mrIid) : \(error.localizedDescription)"
            store.lastErrorIsAuth = {
                if case .unauthorized = error as? MRWatcherError { return true }
                return false
            }()
        }
    }

    func playManualPipelineAction(
        _ action: ManualPipelineAction,
        projectId: Int,
        mrIid: Int
    ) async {
        guard !store.launchingManualPipelineJobIds.contains(action.jobId) else { return }
        store.launchingManualPipelineJobIds.insert(action.jobId)
        defer { store.launchingManualPipelineJobIds.remove(action.jobId) }

        do {
            try await gitlab.playJob(projectId: projectId, jobId: action.jobId)
            await refresh(projectId: projectId, mrIid: mrIid)
        } catch {
            store.lastError = "\(action.kind.title) !\(mrIid) : \(error.localizedDescription)"
            store.lastErrorIsAuth = {
                if case .unauthorized = error as? MRWatcherError { return true }
                return false
            }()
        }
    }

    private func refreshJiraStatus(for key: MRKey) async {
        let jiraPublicationToken = Self.latestJiraPublicationToken
        guard jira.isAvailable else {
            guard Self.latestJiraPublicationToken == jiraPublicationToken else { return }
            store.jiraError = jira.availabilityErrorDescription
            return
        }
        guard let mr = (store.mrs + store.reviewedMRs + store.reviewableMRs).first(where: {
                  MRKey(projectId: $0.projectId, iid: $0.iid) == key
              }),
              let issueKey = extractProdTicket(from: mr) else {
            return
        }
        do {
            let status = try await jira.fetchIssueStatus(issueKey: issueKey)
            guard Self.latestJiraPublicationToken == jiraPublicationToken,
                  store.isDisplayingMR(key: key) else {
                return
            }
            store.jiraStatuses[key] = status
            store.jiraError = nil
        } catch {
            guard Self.latestJiraPublicationToken == jiraPublicationToken,
                  store.isDisplayingMR(key: key) else {
                return
            }
            store.jiraError = "Jira \(issueKey) : \(jira.sanitizedErrorDescription(for: error))"
        }
    }

    private func loadManualPipelineActions(for mr: MRSummary, key: MRKey) async {
        guard !Task.isCancelled,
              let pipelineId = mr.headPipeline?.id,
              let token = store.beginManualPipelineActionsLoad(
                  for: key,
                  pipelineId: pipelineId
              ) else {
            return
        }
        do {
            let result = try await gitlab.fetchManualPipelineActions(
                projectId: key.projectId,
                pipelineId: pipelineId
            )
            guard !Task.isCancelled else { return }
            store.updateManualPipelineActions(
                result,
                for: key,
                pipelineId: pipelineId,
                token: token
            )
        } catch {
            store.failManualPipelineActionsLoad(
                for: key,
                pipelineId: pipelineId,
                token: token
            )
        }
    }

    private func scheduleManualPipelineActions(for actionMRs: [MRKey: MRSummary]) {
        manualPipelineActionsTask?.cancel()
        store.invalidateManualPipelineActions(for: actionMRs.keys)

        let mrsToLoad = actionMRs
            .sorted { lhs, rhs in
                lhs.key.projectId == rhs.key.projectId
                    ? lhs.key.iid < rhs.key.iid
                    : lhs.key.projectId < rhs.key.projectId
            }
            .prefix(Self.manualPipelineActionMRLimit)

        manualPipelineActionsTask = Task { [weak self] in
            guard let self else { return }

            for batchStart in stride(
                from: 0,
                to: mrsToLoad.count,
                by: Self.manualPipelineActionConcurrencyLimit
            ) {
                guard !Task.isCancelled else { return }
                let batchEnd = min(
                    batchStart + Self.manualPipelineActionConcurrencyLimit,
                    mrsToLoad.count
                )
                let batch = mrsToLoad[batchStart..<batchEnd]

                await withTaskGroup(of: Void.self) { group in
                    for (key, mr) in batch {
                        group.addTask { [weak self] in
                            guard !Task.isCancelled, let self else { return }
                            await self.loadManualPipelineActions(for: mr, key: key)
                        }
                    }
                    await group.waitForAll()
                }
            }
        }
    }

    func triggerBuildAffected(projectId: Int, mrIid: Int, oldPipelineId: Int?) async {
        // Attendre que le nouveau pipeline apparaisse (différent de l'ancien)
        var newPipelineId: Int? = nil
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            guard let detail = try? await gitlab.fetchMRDetail(projectId: projectId, mrIid: mrIid),
                  let pipeline = detail.headPipeline else { continue }
            if pipeline.id != oldPipelineId {
                newPipelineId = pipeline.id
                break
            }
        }
        guard let pipelineId = newPipelineId else { return }  // timeout silencieux — rebase pas encore visible

        // Attendre que le job "build affected" soit en statut "manual" (playable)
        var jobId: Int? = nil
        let jobDeadline = Date().addingTimeInterval(60)
        while Date() < jobDeadline {
            if let (id, status) = try? await gitlab.findBuildAffectedJob(projectId: projectId, pipelineId: pipelineId) {
                if status == "manual" {
                    jobId = id
                    break
                }
                // status == "created" ou autre → job pas encore playable, continuer à attendre
            }
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
        }
        guard let jobId else { return }  // pas de job build affected en statut manual dans ce pipeline — silencieux

        do {
            try await gitlab.playJob(projectId: projectId, jobId: jobId)
            let webUrl = (try? await gitlab.fetchMRDetail(projectId: projectId, mrIid: mrIid))?.webUrl ?? ""
            NotificationService.shared.notify(
                identifier: "build-affected-\(projectId)-\(mrIid)",
                title: "Build affected lancé — !\(mrIid)",
                body: "Le job build affected a été déclenché.",
                url: webUrl
            )
        } catch {
            store.lastError = "Build affected !\(mrIid) : \(error.localizedDescription)"
        }
    }

    func pollNow() async {
        guard !store.isLoading else { return }
        let result = await poll(
            store: store,
            gitlab: gitlab,
            jira: jira,
            shouldBootstrapRecentlyMergedMRs: shouldBootstrapRecentlyMergedMRs,
            shouldBootstrapReviewedMRs: shouldBootstrapReviewedMRs,
            reviewedRefreshCursor: reviewedRefreshCursor
        )
        if let result {
            shouldBootstrapRecentlyMergedMRs = false
            shouldBootstrapReviewedMRs = false
            reviewedRefreshCursor = result.reviewedRefreshCursor
        }
    }

    private func poll(
        store: StateStore,
        gitlab: GitLabService,
        jira: JiraService,
        shouldBootstrapRecentlyMergedMRs: Bool,
        shouldBootstrapReviewedMRs: Bool,
        reviewedRefreshCursor: Int
    ) async -> PollResult? {
        await MainActor.run { store.isLoading = true; store.lastError = nil; store.lastErrorIsAuth = false }
        do {
            let mrs = try await gitlab.fetchMyOpenMRs()
            let recentlyMergedMRs = shouldBootstrapRecentlyMergedMRs
                ? try await gitlab.fetchMyRecentlyMergedMRs()
                : []
            let eventPageLimit = shouldBootstrapReviewedMRs
                ? Self.reviewedEventsBootstrapPageLimit
                : Self.reviewedEventsPollingPageLimit
            let eventReviewedKeys = (try? await gitlab.fetchMyCommentedMRKeys(
                maxPages: eventPageLimit
            )) ?? []
            let persistedReviewedKeys = await MainActor.run {
                store.currentReviewedMRKeys()
            }
            let dismissedReviewedKeys = await MainActor.run {
                store.currentDismissedReviewedMRKeys()
            }
            let previousReviewedMRs = await MainActor.run {
                store.reviewedMRs
            }
            let previousReviewStatuses = await MainActor.run {
                store.reviewStatuses
            }
            let previousReviewableMRs = await MainActor.run {
                store.reviewableMRs
            }
            let previousReviewableStatuses = await MainActor.run {
                store.reviewableStatuses
            }

            // Snapshot opened keys before this poll so we can detect disappearances
            let previousOpenedKeys = await MainActor.run {
                Set(store.mrs.filter { $0.state == "opened" }.map { MRKey(projectId: $0.projectId, iid: $0.iid) })
            }
            let retainedMergedMRs = await MainActor.run {
                store.mrs.filter { $0.state == "merged" && !store.dismissedKeys.contains(MRKey(projectId: $0.projectId, iid: $0.iid)) }
            }

            var approvals: [MRKey: MRApprovals] = [:]
            var enrichedMRs: [MRSummary] = []
            var mergedMRs: [MRSummary] = recentlyMergedMRs
            for mr in mrs {
                if Task.isCancelled { return nil }
                let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                let detailed = (try? await gitlab.fetchMRDetail(projectId: mr.projectId, mrIid: mr.iid)) ?? mr
                if detailed.state == "merged" {
                    mergedMRs.append(detailed)
                } else {
                    enrichedMRs.append(detailed)
                }
                if let appr = try? await gitlab.fetchApprovals(projectId: mr.projectId, mrIid: mr.iid) {
                    approvals[key] = appr
                }
            }

            let authoredMRKeys = Set(mrs.map { MRKey(projectId: $0.projectId, iid: $0.iid) })
            let reviewedKeys = Set(
                persistedReviewedKeys
                    .union(eventReviewedKeys)
                    .filter { $0.projectId > 0 && $0.iid > 0 }
            )
            .subtracting(authoredMRKeys)
            .subtracting(dismissedReviewedKeys)
            var reviewedMRsByKey = Dictionary(
                uniqueKeysWithValues: previousReviewedMRs.compactMap { mr in
                    let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                    return reviewedKeys.contains(key) ? (key, mr) : nil
                }
            )
            var reviewStatuses = previousReviewStatuses.filter {
                reviewedKeys.contains($0.key)
            }
            var retainedReviewedKeys = reviewedKeys
            let newlyCommentedKeys: Set<MRKey> = eventReviewedKeys.subtracting(
                persistedReviewedKeys
            )
            let newReviewedKeySet: Set<MRKey> = newlyCommentedKeys.intersection(
                reviewedKeys
            )
            let newReviewedKeys = newReviewedKeySet
                .sorted {
                    $0.projectId == $1.projectId
                        ? $0.iid < $1.iid
                        : $0.projectId < $1.projectId
                }
            let existingReviewedKeySet: Set<MRKey> = reviewedKeys.subtracting(
                Set(newReviewedKeys)
            )
            let existingReviewedKeys = existingReviewedKeySet
                .sorted {
                    $0.projectId == $1.projectId
                        ? $0.iid < $1.iid
                        : $0.projectId < $1.projectId
                }
            let boundedCursor = existingReviewedKeys.isEmpty
                ? 0
                : reviewedRefreshCursor % existingReviewedKeys.count
            let rotatedExistingKeys = Array(existingReviewedKeys[boundedCursor...])
                + Array(existingReviewedKeys[..<boundedCursor])
            let newKeysToRefresh = Array(
                newReviewedKeys.prefix(Self.newlyDiscoveredReviewDetailLimit)
            )
            let existingCapacity = Self.reviewedMRDetailLimit - newKeysToRefresh.count
            let existingKeysToRefresh = Array(
                rotatedExistingKeys.prefix(existingCapacity)
            )
            let refreshKeys = newKeysToRefresh + existingKeysToRefresh
            let nextReviewedRefreshCursor = existingReviewedKeys.isEmpty
                ? 0
                : (boundedCursor + existingKeysToRefresh.count) % existingReviewedKeys.count
            for key in refreshKeys {
                if Task.isCancelled { return nil }
                do {
                    let detail = try await gitlab.fetchMRDetail(
                        projectId: key.projectId,
                        mrIid: key.iid
                    )
                    guard detail.state == "opened" else {
                        retainedReviewedKeys.remove(key)
                        reviewedMRsByKey[key] = nil
                        reviewStatuses[key] = nil
                        continue
                    }
                    reviewedMRsByKey[key] = detail
                    if let status = try? await gitlab.fetchApprovals(
                        projectId: key.projectId,
                        mrIid: key.iid
                    ) {
                        guard status.hasCurrentUserComment else {
                            retainedReviewedKeys.remove(key)
                            reviewedMRsByKey[key] = nil
                            reviewStatuses[key] = nil
                            continue
                        }
                        reviewStatuses[key] = status
                    } else if let previousStatus = previousReviewStatuses[key] {
                        reviewStatuses[key] = previousStatus
                    }
                } catch {
                    if case MRWatcherError.invalidResponse(404) = error {
                        retainedReviewedKeys.remove(key)
                        reviewedMRsByKey[key] = nil
                        reviewStatuses[key] = nil
                        continue
                    }
                }
            }
            let reviewedMRs = reviewedMRsByKey.values.sorted {
                $0.createdAt > $1.createdAt
            }

            var reviewableMRs = previousReviewableMRs
            var reviewableStatuses = previousReviewableStatuses
            if let labelMRs = try? await gitlab.fetchOpenReviewableMRs() {
                let username = await MainActor.run {
                    ConfigManager.shared.gitlabUsername ?? ""
                }
                let candidates = labelMRs.filter { mr in
                    guard !mr.isDraft,
                          !retainedReviewedKeys.contains(
                            MRKey(projectId: mr.projectId, iid: mr.iid)
                          ) else {
                        return false
                    }
                    return mr.author?.username.caseInsensitiveCompare(username) != .orderedSame
                }

                reviewableMRs = []
                reviewableStatuses = [:]
                for mr in candidates {
                    if Task.isCancelled { return nil }
                    let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                    let detailed = (try? await gitlab.fetchMRDetail(
                        projectId: mr.projectId,
                        mrIid: mr.iid
                    )) ?? mr
                    reviewableMRs.append(detailed)
                    if let status = try? await gitlab.fetchApprovals(
                        projectId: mr.projectId,
                        mrIid: mr.iid
                    ) {
                        reviewableStatuses[key] = status
                    } else if let previousStatus = previousReviewableStatuses[key] {
                        reviewableStatuses[key] = previousStatus
                    }
                }
            }

            // Detect MRs that disappeared from the opened list and fetch their real state
            let newKeys = Set(mrs.map { MRKey(projectId: $0.projectId, iid: $0.iid) })
            let disappearedKeys = previousOpenedKeys.subtracting(newKeys)
            for key in disappearedKeys {
                if Task.isCancelled { return nil }
                if let detail = try? await gitlab.fetchMRDetail(projectId: key.projectId, mrIid: key.iid),
                   detail.state == "merged" {
                    mergedMRs.append(detail)
                }
                // If state == "closed" → ignore silently
            }

            let jiraPublicationToken = UUID()
            await MainActor.run {
                store.update(
                    mrs: enrichedMRs,
                    mergedMRs: mergedMRs,
                    approvals: approvals,
                    notifyAboutMerges: !shouldBootstrapRecentlyMergedMRs
                )
                store.replaceReviewedMRKeys(retainedReviewedKeys)
                store.updateReviewedMRs(reviewedMRs, statuses: reviewStatuses)
                store.updateReviewableMRs(reviewableMRs, statuses: reviewableStatuses)
                // Jira runs after the GitLab result is visible, so grouping initially
                // falls back to the non-Jira order instead of blocking the first render.
                store.jiraStatuses = [:]
                store.isLoading = false
                store.lastSuccessfulPollAt = Date()
                Self.latestJiraPublicationToken = jiraPublicationToken
            }

            let actionMRs = Dictionary(
                (enrichedMRs + reviewedMRs + reviewableMRs).map {
                    (MRKey(projectId: $0.projectId, iid: $0.iid), $0)
                },
                uniquingKeysWith: { latest, _ in latest }
            )
            await MainActor.run {
                self.scheduleManualPipelineActions(for: actionMRs)
            }

            let jiraMRs = Dictionary(
                (
                    enrichedMRs
                        + mergedMRs
                        + retainedMergedMRs
                        + reviewedMRs
                        + reviewableMRs
                ).map {
                    (MRKey(projectId: $0.projectId, iid: $0.iid), $0)
                },
                uniquingKeysWith: { latest, _ in latest }
            ).values
            var newJiraStatuses: [MRKey: JiraIssueStatus] = [:]
            var jiraError: String?
            if jira.isAvailable {
                for mr in jiraMRs {
                    if Task.isCancelled {
                        return PollResult(reviewedRefreshCursor: nextReviewedRefreshCursor)
                    }
                    guard let issueKey = extractProdTicket(from: mr) else { continue }
                    let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                    do {
                        let status = try await jira.fetchIssueStatus(issueKey: issueKey)
                        newJiraStatuses[key] = status
                    } catch {
                        if jiraError == nil {
                            jiraError = "Jira \(issueKey) : \(jira.sanitizedErrorDescription(for: error))"
                        }
                    }
                }
            } else {
                jiraError = jira.availabilityErrorDescription
            }

            await MainActor.run {
                guard Self.latestJiraPublicationToken == jiraPublicationToken else { return }
                store.jiraError = jiraError
                let abandonedReviewableKeys = Set(
                    store.reviewableMRs.compactMap { mr in
                        let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                        return newJiraStatuses[key].map(isAbandonedTicket) == true ? key : nil
                    }
                )
                if !abandonedReviewableKeys.isEmpty {
                    let remainingReviewableMRs = store.reviewableMRs.filter {
                        !abandonedReviewableKeys.contains(
                            MRKey(projectId: $0.projectId, iid: $0.iid)
                        )
                    }
                    store.updateReviewableMRs(
                        remainingReviewableMRs,
                        statuses: store.reviewableStatuses
                    )
                }
                let displayedKeys = Set(
                    (store.mrs + store.reviewedMRs + store.reviewableMRs).map {
                        MRKey(projectId: $0.projectId, iid: $0.iid)
                    }
                )
                store.jiraStatuses = newJiraStatuses.filter {
                    displayedKeys.contains($0.key)
                }
            }
            return PollResult(reviewedRefreshCursor: nextReviewedRefreshCursor)
        } catch {
            await MainActor.run {
                store.lastError = error.localizedDescription
                store.lastErrorIsAuth = { if case .unauthorized = error as? MRWatcherError { return true }; return false }()
                store.isLoading = false
            }
            return nil
        }
    }
}

private extension Int {
    func atLeast(_ minimum: Int) -> Int { self <= 0 ? minimum : self }
}

private func extractProdTicket(from mr: MRSummary) -> String? {
    func find(in s: String) -> String? {
        guard let range = s.range(of: #"PROD-\d+"#, options: .regularExpression) else { return nil }
        return String(s[range])
    }
    return find(in: mr.sourceBranch) ?? find(in: mr.title)
}

private func isAbandonedTicket(_ status: JiraIssueStatus) -> Bool {
    let normalizedName = status.name
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    return normalizedName.caseInsensitiveCompare("TICKET ABANDONNÉ") == .orderedSame
}
