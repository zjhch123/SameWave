import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsNavigation {
    enum Tab: Hashable { case ai, vocabulary }
    var selectedTab: Tab = .ai
    var presentedHost: UUID? {
        didSet {
            if oldValue != nil && presentedHost == nil { aiDraft.cancelRequests() }
        }
    }
    let aiSettings: AISettings
    let aiDraft: AISettingsDraft
    let vocabularyEditor: VocabularyEditorStore
    private struct Host {
        let id: UUID
        weak var window: NSWindow?
    }
    private var hosts: [Host] = []
    private var pendingPresentation = false

    init(aiSettings: AISettings, vocabularyEditor: VocabularyEditorStore) {
        self.aiSettings = aiSettings
        aiDraft = AISettingsDraft(settings: aiSettings)
        self.vocabularyEditor = vocabularyEditor
    }

    // SwiftUI can retain a dismissed sheet without firing onDisappear. Route by
    // actual window visibility so those retained views cannot receive new requests.
    func register(_ host: UUID, window: NSWindow) {
        hosts.removeAll { $0.id == host || $0.window == nil }
        hosts.append(Host(id: host, window: window))
        presentPendingSettings()
    }

    func unregister(_ host: UUID) {
        hosts.removeAll { $0.id == host }
        if presentedHost == host { presentedHost = nil }
    }

    func openSettings() {
        guard presentedHost == nil else { return }
        presentedHost = hosts.last { $0.window?.isVisible == true }?.id
        pendingPresentation = presentedHost == nil
    }

    func presentPendingSettings() {
        if pendingPresentation { openSettings() }
    }

    func openAISettings() {
        selectedTab = .ai
        openSettings()
    }
}

/// Each main/preparation surface hosts a native sheet using the same shared settings.
struct SettingsSheet: ViewModifier {
    @Environment(SettingsNavigation.self) private var navigation
    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        content
            .background(SettingsHostWindow { window in
                navigation.register(hostID, window: window)
            })
            .onAppear { navigation.presentPendingSettings() }
            .onDisappear { navigation.unregister(hostID) }
            .sheet(isPresented: Binding(
                get: { navigation.presentedHost == hostID },
                set: { if !$0 && navigation.presentedHost == hostID { navigation.presentedHost = nil } }
            )) {
                SettingsView()
            }
    }
}

private struct SettingsHostWindow: NSViewRepresentable {
    let register: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> HostView { HostView(register: register) }
    func updateNSView(_ view: HostView, context: Context) { view.register = register }

    final class HostView: NSView {
        var register: @MainActor (NSWindow) -> Void
        init(register: @escaping @MainActor (NSWindow) -> Void) {
            self.register = register
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                register(window)
                NotificationCenter.default.addObserver(self, selector: #selector(becameKey),
                    name: NSWindow.didBecomeKeyNotification, object: window)
            }
        }
        @objc private func becameKey(_ notification: Notification) {
            if let window { register(window) }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
            }.padding(16)
            Picker("Settings", selection: $navigation.selectedTab) {
                Text("AI Services").tag(SettingsNavigation.Tab.ai)
                Text("Vocabulary").tag(SettingsNavigation.Tab.vocabulary)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            // Keep both drafts mounted when switching tabs, including pending edits.
            ZStack {
                AISettingsView(draft: navigation.aiDraft)
                    .opacity(navigation.selectedTab == .ai ? 1 : 0)
                    .disabled(navigation.selectedTab != .ai)
                    .allowsHitTesting(navigation.selectedTab == .ai)
                    .accessibilityHidden(navigation.selectedTab != .ai)
                VocabularyEditorView(editor: navigation.vocabularyEditor, isEmbeddedInSettings: true)
                    .opacity(navigation.selectedTab == .vocabulary ? 1 : 0)
                    // Its focus and keyboard handlers already check the active tab.
                    // Disabling the whole subtree makes every row update on each switch.
                    .allowsHitTesting(navigation.selectedTab == .vocabulary)
                    .accessibilityHidden(navigation.selectedTab != .vocabulary)
            }
        }
        .frame(width: 600, height: 540)
    }
}

struct SettingsCommands: Commands {
    let navigation: SettingsNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "control")
                navigation.openSettings()
            }.keyboardShortcut(",", modifiers: .command)
        }
    }
}
