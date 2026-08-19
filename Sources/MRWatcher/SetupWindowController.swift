import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSObject {
    private var panel: NSPanel?

    func open(store: StateStore, scheduler: PollingScheduler) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = SetupView(
            onDismiss: {
                self.panel?.close()
                self.panel = nil
                store.isConfigured = ConfigManager.shared.isConfigured
                store.lastError = nil
                store.lastErrorIsAuth = false
                Task { await scheduler.pollNow() }
            },
            onSaved: {
                store.isConfigured = ConfigManager.shared.isConfigured
                Task { await scheduler.pollNow() }
            }
        )
        let hosting = NSHostingController(rootView: content)
        let panelSize = NSSize(width: 480, height: 680)
        hosting.view.setFrameSize(panelSize)
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "MR Watcher — Configuration"
        p.contentViewController = hosting
        p.setContentSize(panelSize)
        p.isFloatingPanel = true
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
    }
}
