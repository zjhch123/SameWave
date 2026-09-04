import AppKit
import AVFoundation
import Speech
import SwiftUI

@main
struct MeetingCaptionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Single integrated main window. Hidden title bar → the traffic-light buttons
        // float over our own 48pt header (TrafficLightConfigurator centers them there).
        Window("同频", id: "control") {
            if let history = delegate.history {
                MainView(coordinator: delegate.coordinator)
                    .frame(minWidth: 940, minHeight: 480)
                    .ignoresSafeArea(.container, edges: .top)
                    .background(TrafficLightConfigurator(headerHeight: 48))
                    .modelContainer(history.container)
            } else {
                StorageFailureView(message: delegate.storageError ?? "未知错误")
                    .frame(minWidth: 640, minHeight: 360)
            }
        }
        .windowStyle(.hiddenTitleBar)

        // Insight and speech-vocabulary configuration (⌘,). SwiftUI wires this
        // to the standard "同频 ▸ 设置…" menu item automatically.
        Settings {
            SettingsView(
                insightSettings: delegate.insightSettings,
                speechVocabularySettings: delegate.speechVocabularySettings
            )
        }

        // Lightweight menu-bar icon for quick access / quit.
        MenuBarExtra("同频", systemImage: "captions.bubble") {
            Button("显示主窗口") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: CaptureCoordinator
    /// Shared persistent history store; also feeds the sidebar's @Query.
    let history: MeetingHistoryStore?
    let storageError: String?
    /// User configuration for AI insights (provider + Keychain-stored key).
    let insightSettings: InsightSettings
    /// User-managed local vocabulary for English speech recognition.
    let speechVocabularySettings: SpeechVocabularySettings

    override init() {
        let insightSettings = InsightSettings()
        self.insightSettings = insightSettings
        let speechVocabularySettings = SpeechVocabularySettings()
        self.speechVocabularySettings = speechVocabularySettings
        coordinator = CaptureCoordinator(
            speechVocabularySettings: speechVocabularySettings
        )
        do {
            history = try MeetingHistoryStore()
            storageError = nil
        } catch {
            history = nil
            storageError = error.localizedDescription
        }
        super.init()
        coordinator.history = history
        // Wire the insight engine with the user's settings so live captions can be
        // summarized (and history meetings generated on demand).
        coordinator.insights = InsightEngine(settings: insightSettings)
        coordinator.refiner = TranscriptRefiner(
            settings: insightSettings,
            vocabularySettings: speechVocabularySettings
        )
        coordinator.titleGenerator = MeetingTitleGenerator(settings: insightSettings)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show in Dock; app has a main window

        // Recover an interrupted meeting (quit/crash while recording or paused): it
        // comes back as a paused, resumable session. Pure disk read — no capture — so
        // it's safe to do first thing.
        coordinator.recoverUnfinishedSession()

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
            Label("无法打开会议数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .padding(40)
    }
}
