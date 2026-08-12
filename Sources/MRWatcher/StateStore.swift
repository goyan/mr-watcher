import Foundation
import Observation

struct MRKey: Hashable {
    let projectId: Int
    let iid: Int
}

struct WatchEvent: Identifiable {
    let id: UUID
    let kind: WatchEventKind
    let mrTitle: String
    let webUrl: String
    let createdAt: Date
}

enum WatchEventKind {
    case ciFailure, ciSuccess, newComment, merged
}

@MainActor
@Observable
final class StateStore {
    var mrs: [MRSummary] = []
    var approvals: [MRKey: MRApprovals] = [:]
    var events: [WatchEvent] = []
    var isLoading: Bool = false
    var lastError: String? = nil
    var dismissedKeys: Set<MRKey> = []

    var isConfigured: Bool { ConfigManager.shared.isConfigured }

    private let maxEvents = 50

    func dismiss(key: MRKey) {
        dismissedKeys.insert(key)
        mrs.removeAll { MRKey(projectId: $0.projectId, iid: $0.iid) == key }
    }

    func update(mrs: [MRSummary], mergedMRs: [MRSummary] = [], approvals: [MRKey: MRApprovals]) {
        var newEvents: [WatchEvent] = []

        // Detect merges: MRs that disappeared from the opened list and were confirmed merged
        for mr in mergedMRs {
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            guard !dismissedKeys.contains(key) else { continue }
            newEvents.append(WatchEvent(
                id: UUID(), kind: .merged,
                mrTitle: mr.title, webUrl: mr.webUrl, createdAt: Date()
            ))
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
                    newEvents.append(WatchEvent(
                        id: UUID(), kind: kind,
                        mrTitle: mr.title,
                        webUrl: mr.headPipeline?.webUrl ?? mr.webUrl,
                        createdAt: Date()
                    ))
                }
            }

            // New comment notification (only for opened MRs)
            if mr.state == "opened", let prev = prevMR, mr.notesCount > prev.notesCount {
                newEvents.append(WatchEvent(
                    id: UUID(), kind: .newComment,
                    mrTitle: mr.title, webUrl: mr.webUrl, createdAt: Date()
                ))
            }
        }

        for event in newEvents {
            let body: String = switch event.kind {
            case .ciFailure: "Pipeline échoué"
            case .ciSuccess: "Pipeline réussi"
            case .newComment: "Nouveau commentaire"
            case .merged: event.mrTitle
            }
            let title: String = switch event.kind {
            case .merged: "MR mergée 🎉"
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
        self.events = Array((newEvents + self.events).prefix(maxEvents))
    }

    func clearEvents() { events = [] }
}
