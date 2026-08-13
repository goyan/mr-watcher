import SwiftUI

@main
struct MRWatcherApp: App {
    @State private var store: StateStore
    @State private var seenEventIds: Set<UUID> = []

    private let scheduler: PollingScheduler
    private let setupController = SetupWindowController()

    init() {
        let s = StateStore()
        let svc = GitLabService(config: .shared)
        let jira = JiraService(config: .shared)
        let sched = PollingScheduler(store: s, gitlab: svc, jira: jira)
        _store = State(initialValue: s)
        scheduler = sched
        Task {
            await NotificationService.shared.requestAuthorization()
            sched.start()
        }
    }

    private var unreadCount: Int {
        store.events.filter { !seenEventIds.contains($0.id) }.count
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, scheduler: scheduler, setupController: setupController) {
                seenEventIds.formUnion(store.events.map(\.id))
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                if unreadCount > 0 {
                    Text("\(unreadCount)").font(.caption.bold())
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
