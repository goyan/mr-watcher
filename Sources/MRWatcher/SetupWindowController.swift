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
            }
        )
        let hosting = NSHostingController(rootView: content)
        hosting.view.setFrameSize(NSSize(width: 380, height: 440))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "MR Watcher — Configuration"
        p.contentViewController = hosting
        p.setContentSize(NSSize(width: 380, height: 440))
        p.isFloatingPanel = true
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
    }
}
