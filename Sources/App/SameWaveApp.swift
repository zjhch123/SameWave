import AppKit
import AVFoundation
import Speech
import SwiftUI

@main
struct SameWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Single integrated main window. Hidden title bar → the traffic-light buttons
        // float over our own 48pt header (TrafficLightConfigurator centers them there).
        Window("SameWave", id: "control") {
            if let history = delegate.history {
                MainView(coordinator: delegate.coordinator)
                    .frame(minWidth: 940, minHeight: 480)
                    .ignoresSafeArea(.container, edges: .top)
                    .background(TrafficLightConfigurator(headerHeight: 48))
                    .modelContainer(history.container)
                    .environment(delegate.aiSettings)
                    .modifier(SettingsSheet())
                    .environment(delegate.settingsNavigation)
            } else {
                StorageFailureView(message: delegate.storageError ?? String(localized: "Unknown error"))
                    .frame(minWidth: 640, minHeight: 360)
            }
        }
        .windowStyle(.hiddenTitleBar)

        .commands { SettingsCommands(navigation: delegate.settingsNavigation) }

        // Lightweight menu-bar icon for quick access / quit.
        MenuBarExtra("SameWave", systemImage: "captions.bubble") {
            Button("Show Main Window") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: CaptureCoordinator
    /// Shared persistent history store; also feeds the sidebar's @Query.
    let history: MeetingHistoryStore?
    let storageError: String?
    /// Shared AI configuration used by every AI feature.
    let aiSettings: AISettings
    let settingsNavigation: SettingsNavigation
    /// User-managed local vocabulary for English speech recognition.
    let speechVocabularySettings: SpeechVocabularySettings
    /// Owns personal vocabulary editing and extraction for this app session.
    let vocabularyEditor: VocabularyEditorStore

    override init() {
        let aiSettings = AISettings()
        self.aiSettings = aiSettings
        let speechVocabularySettings = SpeechVocabularySettings()
        self.speechVocabularySettings = speechVocabularySettings
        vocabularyEditor = VocabularyEditorStore(aiSettings: aiSettings, settings: speechVocabularySettings)
        settingsNavigation = SettingsNavigation(aiSettings: aiSettings, vocabularyEditor: vocabularyEditor)
        coordinator = CaptureCoordinator(
            speechVocabularySettings: speechVocabularySettings
        )
        do {
            history = try MeetingHistoryStore(configuration:
                ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
                    ? .init(isStoredInMemoryOnly: true) : nil
            )
            storageError = nil
        } catch {
            history = nil
            storageError = error.localizedDescription
        }
        super.init()
        coordinator.history = history
        // Wire the insight engine with the user's settings so live captions can be
        // summarized (and history meetings generated on demand).
        if let history {
            coordinator.insights = InsightEngine(settings: aiSettings, history: history)
        }
        aiSettings.onDisable = { [weak self] in
            self?.coordinator.cancelAIWork()
            self?.vocabularyEditor.importer.stop()
            self?.settingsNavigation.aiDraft.cancelRequests()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show in Dock; app has a main window

        // Hosted domain tests own their fixtures and must not restore real meetings
        // or request capture permissions from the unsigned test application.
        guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }

        // Restore the last selection; interrupted meetings remain paused until resumed.
        coordinator.restoreSelection()

        // Pre-request speech-recognition authorization at launch (main runloop is
        // ready here, so the system prompt appears reliably). The completion runs
        // on a background XPC thread — keep it nonisolated (don't touch main-actor
        // state) or Swift 6 actor-isolation checks crash.
        if #available(macOS 26.0, *) {
            Self.preflightSpeechAuth()
        }

        // Pre-request microphone access too (we caption the user's own voice by
        // default). Do it slightly after launch, on the main queue, once the app
        // is active and frontmost — requesting during the very first launch tick,
        // before the app is foreground, can let the system prompt be swallowed.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    /// Flush the live transcript on a clean quit so the last few seconds (since the
    /// autosave tick) aren't lost. A crash skips this — but incremental autosave
    /// already bounds the loss to the tick interval.
    func applicationWillTerminate(_ notification: Notification) {
        coordinator.persistNow()
    }

    /// Kick off the speech-auth prompt from a nonisolated context so the
    /// background completion never touches main-actor state.
    @available(macOS 26.0, *)
    nonisolated static func preflightSpeechAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
}

private struct StorageFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Could Not Open Meeting Data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .padding(40)
    }
}
