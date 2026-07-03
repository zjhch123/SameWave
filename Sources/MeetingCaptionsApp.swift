import AppKit
import Speech
import SwiftUI

@main
struct MeetingCaptionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Main control window.
        Window("会议字幕", id: "control") {
            ControlView(coordinator: delegate.coordinator, overlay: delegate.overlay)
                .frame(minWidth: 360, minHeight: 420)
        }
        .windowResizability(.contentSize)

        // Lightweight menu-bar icon for quick overlay toggle.
        MenuBarExtra("Captions", systemImage: "captions.bubble") {
            Button("显示悬浮字幕") { delegate.overlay.show() }
            Button("隐藏悬浮字幕") { delegate.overlay.hide() }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = CaptureCoordinator()
    lazy var overlay = OverlayController(coordinator: coordinator)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show in Dock; app has a main window
        coordinator.refreshProcesses()
        overlay.show()

        // Pre-request speech-recognition authorization at launch (main runloop is
        // ready here, so the system prompt appears reliably). The completion runs
        // on a background XPC thread — keep it nonisolated (don't touch main-actor
        // state) or Swift 6 actor-isolation checks crash.
        if #available(macOS 26.0, *) {
            Self.preflightSpeechAuth()
        }

        // Test automation hook: MC_AUTOSTART=lang ("en" or "zh") starts a
        // global-tap session immediately on launch.
        if let auto = ProcessInfo.processInfo.environment["MC_AUTOSTART"] {
            let lang = auto.split(separator: ":").first.map(String.init) ?? "en"
            coordinator.meetingLanguage = (lang == "zh") ? .chinese : .english
            // Give the app a moment to settle, then start on all system audio.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                coordinator.startGlobal()
            }
        }
    }

    /// Kick off the speech-auth prompt from a nonisolated context so the
    /// background completion never touches main-actor state.
    @available(macOS 26.0, *)
    nonisolated static func preflightSpeechAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
}
