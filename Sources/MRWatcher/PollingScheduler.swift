import Foundation

@MainActor
final class PollingScheduler {
    private let store: StateStore
    private let gitlab: GitLabService
    private var task: Task<Void, Never>?

    private var intervalSeconds: Int {
        max(15, UserDefaults.standard.integer(forKey: "pollIntervalSeconds").atLeast(60))
    }

    init(store: StateStore, gitlab: GitLabService) {
        self.store = store
        self.gitlab = gitlab
    }

    func start() {
        stop()
        task = Task { [store, gitlab] in
            while !Task.isCancelled {
                await PollingScheduler.poll(store: store, gitlab: gitlab)
                try? await Task.sleep(for: .seconds(Double(intervalSeconds)))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func rebase(projectId: Int, mrIid: Int) async throws {
        try await gitlab.rebase(projectId: projectId, mrIid: mrIid)
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
        await PollingScheduler.poll(store: store, gitlab: gitlab)
    }

    private static func poll(store: StateStore, gitlab: GitLabService) async {
        await MainActor.run { store.isLoading = true; store.lastError = nil }
        do {
            let mrs = try await gitlab.fetchMyOpenMRs()

            // Snapshot opened keys before this poll so we can detect disappearances
            let previousOpenedKeys = await MainActor.run {
                Set(store.mrs.filter { $0.state == "opened" }.map { MRKey(projectId: $0.projectId, iid: $0.iid) })
            }

            var approvals: [MRKey: MRApprovals] = [:]
            var enrichedMRs: [MRSummary] = []
            var mergedMRs: [MRSummary] = []
            for mr in mrs {
                if Task.isCancelled { return }
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

            // Detect MRs that disappeared from the opened list and fetch their real state
            let newKeys = Set(mrs.map { MRKey(projectId: $0.projectId, iid: $0.iid) })
            let disappearedKeys = previousOpenedKeys.subtracting(newKeys)
            for key in disappearedKeys {
                if Task.isCancelled { return }
                if let detail = try? await gitlab.fetchMRDetail(projectId: key.projectId, mrIid: key.iid),
                   detail.state == "merged" {
                    mergedMRs.append(detail)
                }
                // If state == "closed" → ignore silently
            }

            await MainActor.run {
                store.update(mrs: enrichedMRs, mergedMRs: mergedMRs, approvals: approvals)
                store.isLoading = false
            }
        } catch {
            await MainActor.run {
                store.lastError = error.localizedDescription
                store.isLoading = false
            }
        }
    }
}

private extension Int {
    func atLeast(_ minimum: Int) -> Int { self <= 0 ? minimum : self }
}
