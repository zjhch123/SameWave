import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MainWindowPresentation: NSObject, NSWindowDelegate {
    var isSimpleMode: Bool {
        get { simpleModeRequested }
        set {
            simpleModeRequested = newValue && canEnterSimpleMode
            updateWindows()
        }
    }

    private var simpleModeRequested = false
    private let coordinator: CaptureCoordinator
    @ObservationIgnored private(set) var panel: NSPanel?
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private let frameAutosaveName: String?

    var hasMainWindow: Bool { mainWindow != nil }
    var canEnterSimpleMode: Bool { coordinator.isRunning }

    init(coordinator: CaptureCoordinator, frameAutosaveName: String? = nil) {
        self.coordinator = coordinator
        self.frameAutosaveName = frameAutosaveName
        super.init()
    }

    func attach(to window: NSWindow) {
        mainWindow = window
        if !canEnterSimpleMode { simpleModeRequested = false }
        updateWindows()
    }

    func showFullWindow() {
        if isSimpleMode { isSimpleMode = false }
        else { bringMainWindowForward() }
    }

    private func updateWindows() {
        guard let mainWindow else { return }
        if isSimpleMode {
            let panel = panel ?? makePanel(coordinator: coordinator, screen: mainWindow.screen)
            mainWindow.orderOut(nil)
            guard !panel.isVisible else { return }
            if NSApp.isActive { panel.makeKeyAndOrderFront(nil) }
            else { panel.orderFrontRegardless() }
        } else if let panel, panel.isVisible {
            panel.orderOut(nil)
            bringMainWindowForward()
        }
    }

    private func bringMainWindowForward() {
        guard let mainWindow else { return }
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel(coordinator: CaptureCoordinator, screen: NSScreen?) -> NSPanel {
        let panel = SubtitlePanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 220),
            styleMask: [.borderless, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = String(localized: "Simple Mode")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 440, height: 180)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        let host = NSHostingView(rootView: SimpleCaptionsView(coordinator: coordinator, onShowFullWindow: { [weak self] in
            self?.showFullWindow()
        })
        .frame(minWidth: 440, minHeight: 180))
        host.sizingOptions = [.minSize]
        panel.contentView = host
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            let frame = NSRect(x: visible.midX - 340, y: visible.minY + 48, width: 680, height: 220)
            panel.setFrame(frame, display: false)
            if let frameAutosaveName {
                panel.setFrameAutosaveName(frameAutosaveName)
                panel.setFrameUsingName(frameAutosaveName)
            }
            panel.setFrame(Self.fitting(panel.frame, in: visible), display: false)
        }
        self.panel = panel
        return panel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        isSimpleMode = false
        return false
    }

    private static func fitting(_ frame: NSRect, in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        return NSRect(x: min(max(frame.minX, visible.minX), visible.maxX - size.width),
            y: min(max(frame.minY, visible.minY), visible.maxY - size.height),
            width: size.width, height: size.height)
    }
}

private final class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performClose(_ sender: Any?) {
        if delegate?.windowShouldClose?(self) ?? true { close() }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performClose(_:)) { return true }
        return super.validateUserInterfaceItem(item)
    }
}

struct MainWindowConfigurator: NSViewRepresentable {
    let presentation: MainWindowPresentation

    func makeNSView(context: Context) -> AttachmentView { AttachmentView(frame: .zero) }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.presentation = presentation
        view.attachToWindow()
    }

    final class AttachmentView: NSView {
        weak var presentation: MainWindowPresentation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachToWindow()
        }

        func attachToWindow() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, let presentation else { return }
                presentation.attach(to: window)
            }
        }
    }
}

struct WindowModeCommands: Commands {
    let presentation: MainWindowPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            if presentation.canEnterSimpleMode || presentation.isSimpleMode {
                Button(presentation.isSimpleMode ? "Show Full Window" : "Simple Mode") {
                    if !presentation.hasMainWindow { openWindow(id: "control") }
                    presentation.isSimpleMode.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
        CommandGroup(after: .windowSize) {
            if presentation.isSimpleMode {
                Button("Show Full Window") { presentation.showFullWindow() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}

struct SameWaveMenu: View {
    let presentation: MainWindowPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Main Window") { show(simple: false) }
        if presentation.canEnterSimpleMode {
            Button("Simple Mode") { show(simple: true) }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }

    private func show(simple: Bool) {
        if !presentation.hasMainWindow { openWindow(id: "control") }
        if simple { presentation.isSimpleMode = true }
        else { presentation.showFullWindow() }
    }
}
