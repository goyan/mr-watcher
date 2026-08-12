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
    case ciFailure, ciSuccess, newComment
}

@MainActor
@Observable
final class StateStore {
    var mrs: [MRSummary] = []
    var approvals: [MRKey: MRApprovals] = [:]
    var events: [WatchEvent] = []
    var isLoading: Bool = false
    var lastError: String? = nil

    var isConfigured: Bool { ConfigManager.shared.isConfigured }

    private let maxEvents = 50

    func update(mrs: [MRSummary], approvals: [MRKey: MRApprovals]) {
        var newEvents: [WatchEvent] = []

        for mr in mrs {
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            let prevMR = self.mrs.first { $0.iid == mr.iid && $0.projectId == mr.projectId }

            // CI change notification
            if let prev = prevMR,
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

            // New comment notification
            if let prev = prevMR, mr.notesCount > prev.notesCount {
                newEvents.append(WatchEvent(
                    id: UUID(), kind: .newComment,
                    mrTitle: mr.title, webUrl: mr.webUrl, createdAt: Date()
                ))
            }

            _ = key  // suppress unused warning
        }

        for event in newEvents {
            let body: String = switch event.kind {
            case .ciFailure: "Pipeline échoué"
            case .ciSuccess: "Pipeline réussi"
            case .newComment: "Nouveau commentaire"
            }
            let notifId = event.webUrl.replacingOccurrences(of: "/", with: "-") + "-\(event.kind)"
            NotificationService.shared.notify(identifier: notifId, title: event.mrTitle, body: body, url: event.webUrl)
        }

        self.mrs = mrs
        self.approvals = approvals
        self.events = Array((newEvents + self.events).prefix(maxEvents))
    }

    func clearEvents() { events = [] }
}
