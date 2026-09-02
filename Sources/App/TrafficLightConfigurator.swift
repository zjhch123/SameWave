import AppKit
import SwiftUI

/// Vertically centers the window's traffic-light buttons within a header of
/// `headerHeight` points (default 48), so they line up with our custom top bar's
/// controls (sidebar toggle, export, inspector title) — all centered on the same
/// baseline. Under `.hiddenTitleBar` the buttons default to y≈19 (near the top);
/// this nudges them down to the header's vertical center.
///
/// Reposition-on-layout: macOS re-lays the buttons on resize/active-state changes,
/// so we re-apply from a window-delegate hook and a light observer.
struct TrafficLightConfigurator: NSViewRepresentable {
    var headerHeight: CGFloat = 48

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(headerHeight: headerHeight) }

    final class Coordinator: NSObject {
        private let headerHeight: CGFloat
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(headerHeight: CGFloat) { self.headerHeight = headerHeight }

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else { reposition(); return }
            self.window = window
            // Re-center whenever the window resizes or becomes key (macOS re-lays
            // the standard buttons on those events).
            let nc = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didBecomeMainNotification] {
                observers.append(nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reposition()
                })
            }
            reposition()
        }

        private func reposition() {
            guard let window else { return }
            let buttons = [NSWindow.ButtonType.closeButton,
                           .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
            guard let first = buttons.first, let container = first.superview else { return }

            // Vertically center each button inside `headerHeight`. The titlebar
            // container is NOT flipped (origin bottom-left), so a larger y sits
            // higher; to move the buttons DOWN we DECREASE y from the top.
            for b in buttons {
                var f = b.frame
                let targetTop = (headerHeight - f.height) / 2      // gap above the button
                f.origin.y = container.bounds.height - f.height - targetTop
                b.frame = f
            }
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
