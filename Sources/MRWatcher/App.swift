import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct MRWatcherApp: App {
    @State private var store: StateStore
    @State private var seenEventIds: Set<UUID> = []
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let scheduler: PollingScheduler
    private let setupController = SetupWindowController()
    private let updaterController = UpdaterController()

    init() {
        UserDefaults.standard.set(0.1, forKey: "NSInitialToolTipDelay")
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
        WindowGroup {
            StatusView(
                store: store,
                scheduler: scheduler,
                setupController: setupController,
                updaterController: updaterController
            )
        }

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
