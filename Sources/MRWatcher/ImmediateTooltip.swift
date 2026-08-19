import AppKit
import SwiftUI

private struct ImmediateTooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.background(ImmediateTooltipHost(text: text))
    }
}

private struct ImmediateTooltipHost: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TooltipTrackingView {
        let view = TooltipTrackingView()
        context.coordinator.configure(view, text: text)
        return view
    }

    func updateNSView(_ view: TooltipTrackingView, context: Context) {
        context.coordinator.configure(view, text: text)
    }

    static func dismantleNSView(_ view: TooltipTrackingView, coordinator: Coordinator) {
        coordinator.teardown(view)
    }

    final class Coordinator {
        private let panel = TooltipPanel()
        private weak var trackingView: TooltipTrackingView?
        private var isHovering = false
        private var text = ""

        deinit {
            panel.close()
        }

        func configure(_ view: TooltipTrackingView, text: String) {
            if trackingView !== view {
                trackingView?.onMouseEntered = nil
                trackingView?.onMouseExited = nil
                trackingView?.onLayout = nil
                trackingView?.onWindowChanged = nil
                trackingView = view
                view.onMouseEntered = { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.isHovering = true
                    self.panel.show(text: self.text, near: view)
                }
                view.onMouseExited = { [weak self] in
                    self?.isHovering = false
                    self?.panel.hide()
                }
                view.onLayout = { [weak self, weak view] in
                    guard let self, self.isHovering, let view else { return }
                    self.panel.show(text: self.text, near: view)
                }
                view.onWindowChanged = { [weak self] in
                    self?.isHovering = false
                    self?.panel.hide()
                }
            }

            self.text = text
            if isHovering {
                panel.show(text: text, near: view)
            }
        }

        func teardown(_ view: TooltipTrackingView) {
            guard trackingView === view else { return }
            isHovering = false
            panel.hide()
            view.onMouseEntered = nil
            view.onMouseExited = nil
            view.onLayout = nil
            view.onWindowChanged = nil
            trackingView = nil
        }
    }
}

private final class TooltipTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onLayout: (() -> Void)?
    var onWindowChanged: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    deinit {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?()
    }
}

private final class TooltipPanel: NSPanel {
    private let tooltipView = TooltipContentView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        isOpaque = false
        contentView = tooltipView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(text: String, near view: NSView) {
        guard let window = view.window else {
            hide()
            return
        }

        let size = tooltipView.update(text: text)
        setContentSize(size)

        let viewRect = view.convert(view.bounds, to: nil)
        let anchor = window.convertToScreen(viewRect)
        guard let screen = screen(containing: anchor, fallback: window.screen) else {
            hide()
            return
        }

        let visibleFrame = screen.visibleFrame
        let x = min(
            max(anchor.midX - (size.width / 2), visibleFrame.minX),
            visibleFrame.maxX - size.width
        )
        let preferredY = anchor.maxY + 8
        let y = preferredY + size.height <= visibleFrame.maxY
            ? preferredY
            : max(visibleFrame.minY, anchor.minY - size.height - 8)

        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    private func screen(containing rect: NSRect, fallback: NSScreen?) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) } ?? fallback ?? NSScreen.main
    }
}

private final class TooltipContentView: NSView {
    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 6
    private let maximumTextWidth: CGFloat = 344
    private let textField = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        textField.font = NSFont.toolTipsFont(ofSize: 0)
        textField.textColor = NSColor.labelColor
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.isSelectable = false
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    func update(text: String) -> NSSize {
        textField.stringValue = text
        textField.preferredMaxLayoutWidth = maximumTextWidth
        let textSize = textField.sizeThatFits(
            NSSize(width: maximumTextWidth, height: .greatestFiniteMagnitude)
        )
        let size = NSSize(
            width: min(maximumTextWidth, ceil(textSize.width)) + (horizontalPadding * 2),
            height: ceil(textSize.height) + (verticalPadding * 2)
        )
        frame.size = size
        textField.frame = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: size.width - (horizontalPadding * 2),
            height: size.height - (verticalPadding * 2)
        )
        return size
    }
}

extension View {
    func immediateTooltip(_ text: String) -> some View {
        modifier(ImmediateTooltipModifier(text: text))
    }
}
