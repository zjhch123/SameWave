import AppKit
import SwiftUI

/// Borderless, always-on-top, non-activating caption overlay.
/// Does not steal focus from the meeting app.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless, .resizable],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .screenSaver                       // above almost everything
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false                  // CRITICAL: app is never "active"
        isReleasedWhenClosed = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }       // allow text selection
    override var canBecomeMain: Bool { false }
}

/// Manages the overlay panel's lifecycle and hosts the SwiftUI content.
@MainActor
final class OverlayController {
    private var panel: FloatingPanel?
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 660, height: 300)
        let rect = NSRect(x: vis.midX - size.width / 2,
                          y: vis.minY + 140,
                          width: size.width, height: size.height)
        let p = FloatingPanel(contentRect: rect)
        p.contentMinSize = NSSize(width: 360, height: 120)

        // The overlay content hosts BOTH the captions view and the invisible
        // translationTask that keeps the Translation session alive.
        let root = OverlayRoot(coordinator: coordinator)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
    }

    func hide() { panel?.orderOut(nil) }

    func toggleClickThrough(_ on: Bool) {
        panel?.ignoresMouseEvents = on
    }
}

/// SwiftUI root of the overlay: captions + the translation pump.
private struct OverlayRoot: View {
    let coordinator: CaptureCoordinator

    var body: some View {
        CaptionsView(store: coordinator.store)
            .modifier(TranslationPump(bridge: coordinator.translation))
    }
}
