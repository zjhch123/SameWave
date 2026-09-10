import AppKit
import Observation
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class SettingsPresentationTests: XCTestCase {
    func testReturnAndEscapeCloseEveryTabWithPreferencesAlreadyPersisted() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        let controller = navigation.aiController
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        for tab in [SettingsNavigation.Tab.general, .ai, .vocabulary] {
            navigation.selectedTab = tab
            for key in ["\r", "\u{1b}"] {
                controller.customModel = "pending-model"
                controller.contextBudgetText = "invalid"
                navigation.vocabularyEditor.manualText = "Pending vocabulary"
                navigation.openSettings()
                try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
                let sheet = try XCTUnwrap(window.attachedSheet)
                sheet.makeKeyAndOrderFront(nil)
                sheet.makeFirstResponder(nil)
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
                    characters: key, charactersIgnoringModifiers: key, isARepeat: false,
                    keyCode: key == "\r" ? 36 : 53))
                sheet.sendEvent(event)
                try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
                XCTAssertEqual(settings.customModel, "pending-model")
                XCTAssertNil(settings.insightContextTokenBudget)
                XCTAssertEqual(controller.customModel, "pending-model")
                XCTAssertEqual(controller.contextBudgetText, "invalid")
                XCTAssertEqual(navigation.vocabularyEditor.manualText, "Pending vocabulary")
            }
        }
    }

    func testReturnInConnectionFieldEndsEditingBeforeClosingSettings() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        navigation.aiController.contextBudgetText = "invalid"
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        navigation.openAISettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let field = try XCTUnwrap(textField(in: sheet.contentView, value: "invalid"))
        sheet.makeKeyAndOrderFront(nil)
        sheet.makeFirstResponder(field)
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        sheet.sendEvent(enter)
        await Task.yield()
        XCTAssertTrue(window.attachedSheet === sheet)
        XCTAssertEqual(navigation.aiController.contextBudgetText, "invalid")
        XCTAssertNil(settings.insightContextTokenBudget)
        sheet.sendEvent(enter)
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        XCTAssertEqual(navigation.aiController.contextBudgetText, "invalid")
    }

    func testNativeTextEditingPersistsBeforeFocusLeavesTheField() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        navigation.aiController.providerID = "custom"
        navigation.aiController.customAPIAddress = "https://example.com/v1"
        navigation.aiController.customModel = "retained-model"
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        navigation.openAISettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let field = try XCTUnwrap(textField(in: sheet.contentView, value: "1000000"))
        sheet.makeKeyAndOrderFront(nil)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        for input in ["65,536", "invalid", "128000"] {
            editor.insertText(input, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            try await Phase2Fixture.waitUntil { settings.contextBudgetText == input }
            XCTAssertTrue(field.currentEditor() === editor)
            XCTAssertEqual(AISettings(defaults: defaults).contextBudgetText, input)
        }
        XCTAssertEqual(settings.insightContextTokenBudget, 128_000)

        let fields = try ["test-key", "https://example.com/v1", "retained-model", "128000"].map { value in
            try XCTUnwrap(textField(in: sheet.contentView, value: value))
        }
        navigation.aiController.isEnabled = false
        try await Phase2Fixture.waitUntil { fields.allSatisfy { !$0.isEnabled } }
        XCTAssertFalse(AISettings(defaults: defaults).isEnabled)
        XCTAssertEqual(settings.customModel, "retained-model")
        XCTAssertEqual(settings.contextBudgetText, "128000")
        navigation.aiController.isEnabled = true
        try await Phase2Fixture.waitUntil { fields.allSatisfy(\.isEnabled) }
        field.selectText(nil)
        XCTAssertNotNil(field.currentEditor())
    }

    private func textField(in view: NSView?, value: String) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.stringValue == value { return field }
        return view.subviews.lazy.compactMap { self.textField(in: $0, value: value) }.first
    }

    func testVocabularyEscapeCancelsOnlyTheRowBeforeClosingSettings() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let saved = SpeechVocabularySettings(defaults: defaults)
        saved.save(["SameWave"])
        let editor = VocabularyEditorStore(aiSettings: settings, settings: saved)
        let navigation = SettingsNavigation(aiSettings: settings, vocabularyEditor: editor)
        navigation.selectedTab = .vocabulary
        navigation.aiController.customModel = "pending-model"
        editor.beginEditing("SameWave")
        editor.editedText = "Uncommitted term"
        editor.focusedField = .saved
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        sheet.makeKeyAndOrderFront(nil)
        try await Phase2Fixture.waitUntil { (sheet.firstResponder as? NSTextView)?.string == "Uncommitted term" }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        sheet.sendEvent(escape)
        try await Phase2Fixture.waitUntil { editor.editingPhrase == nil }
        XCTAssertTrue(window.attachedSheet === sheet)
        XCTAssertEqual(saved.phrases, ["SameWave"])
        XCTAssertEqual(navigation.aiController.customModel, "pending-model")
        sheet.sendEvent(escape)
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
    }

    func testDismissingSettingsEndsModelLoadingAndKeepsPreferences() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        let controller = navigation.aiController
        controller.providerID = "custom"
        controller.apiKey = "test-key"
        controller.customAPIAddress = "https://example.com/v1"
        controller.customModel = "retained-model"
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        controller.fetchModels {
            try await Task.sleep(for: .seconds(60))
            return []
        }
        XCTAssertEqual(controller.modelDiscoveryState, .loading)
        navigation.presentedHost = nil
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        XCTAssertEqual(controller.modelDiscoveryState, .idle)
        XCTAssertTrue(controller.canFetchModels)
        XCTAssertEqual(controller.customModel, "retained-model")
    }

    func testSettingsRoutesToInnermostHostAndWaitsForMainWindow() {
        let defaults = Phase2Fixture.defaults(self)
        let navigation = Phase2Fixture.settingsNavigation(AISettings(defaults: defaults), defaults: defaults)
        navigation.openSettings()
        XCTAssertNil(navigation.presentedHost)
        let main = UUID(), preparation = UUID(), vocabulary = UUID()
        let mainWindow = testWindow(), preparationWindow = testWindow(), vocabularyWindow = testWindow()
        defer { mainWindow.close(); preparationWindow.close(); vocabularyWindow.close() }
        navigation.register(main, window: mainWindow)
        XCTAssertEqual(navigation.presentedHost, main)
        navigation.presentedHost = nil
        navigation.register(preparation, window: preparationWindow)
        navigation.register(vocabulary, window: vocabularyWindow)
        navigation.selectedTab = .vocabulary
        navigation.openAISettings()
        XCTAssertEqual(navigation.selectedTab, .ai)
        XCTAssertEqual(navigation.presentedHost, vocabulary)
        navigation.openSettings()
        XCTAssertEqual(navigation.presentedHost, vocabulary)
        vocabularyWindow.orderOut(nil)
        navigation.presentedHost = nil
        navigation.openSettings()
        XCTAssertEqual(navigation.presentedHost, preparation)
        navigation.openSettings()
        XCTAssertEqual(navigation.presentedHost, preparation)
        preparationWindow.orderOut(nil)
        navigation.presentedHost = nil
        navigation.openSettings()
        XCTAssertEqual(navigation.presentedHost, main)
        navigation.aiController.isEnabled = false
        navigation.openAISettings()
        XCTAssertEqual(navigation.selectedTab, .general)
        XCTAssertEqual(navigation.presentedHost, main)
        navigation.aiController.isEnabled = true
        navigation.openAISettings()
        XCTAssertEqual(navigation.selectedTab, .ai)
        XCTAssertEqual(navigation.presentedHost, main)
    }

    func testEmbeddedVocabularyKeepsOneSettingsSheetAndIndependentVocabularyEdits() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let saved = SpeechVocabularySettings(defaults: defaults)
        saved.save([])
        let editor = VocabularyEditorStore(aiSettings: settings, settings: saved)
        let navigation = SettingsNavigation(aiSettings: settings, vocabularyEditor: editor)
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        let settingsSheet = try XCTUnwrap(window.attachedSheet)
        let initialSize = settingsSheet.frame.size
        navigation.aiController.customModel = "Pending model"
        navigation.aiController.contextBudgetText = "64,000"
        navigation.selectedTab = .vocabulary
        await Task.yield()
        XCTAssertNil(settingsSheet.attachedSheet)
        XCTAssertEqual(settingsSheet.frame.size, initialSize)
        editor.manualText = "XPay"
        editor.addTerms()
        editor.manualText = "Pending manual edit"
        editor.isAddingTerms = true
        editor.focusedField = .manual
        navigation.selectedTab = .general
        await Task.yield()
        XCTAssertTrue(window.attachedSheet === settingsSheet)
        XCTAssertEqual(settingsSheet.frame.size, initialSize)
        XCTAssertEqual(editor.manualText, "Pending manual edit")
        XCTAssertEqual(navigation.aiController.customModel, "Pending model")
        navigation.openAISettings()
        await Task.yield()
        XCTAssertTrue(window.attachedSheet === settingsSheet)
        XCTAssertNil(settingsSheet.attachedSheet)
        XCTAssertEqual(navigation.selectedTab, .ai)
        XCTAssertEqual(navigation.aiController.customModel, "Pending model")
        XCTAssertEqual(settings.insightContextTokenBudget, 64_000)
        XCTAssertEqual(settings.customModel, "Pending model")
        navigation.selectedTab = .vocabulary
        await Task.yield()
        XCTAssertEqual(editor.manualText, "Pending manual edit")
        XCTAssertEqual(settingsSheet.frame.size, initialSize)
        navigation.presentedHost = nil
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        XCTAssertNil(window.attachedSheet?.attachedSheet)
        XCTAssertEqual(navigation.selectedTab, .vocabulary)
        XCTAssertEqual(editor.manualText, "Pending manual edit")
        XCTAssertEqual(saved.phrases, ["XPay"])
        XCTAssertEqual(SpeechVocabularySettings(defaults: defaults).phrases, ["XPay"])
        XCTAssertEqual(AISettings(defaults: defaults).customModel, "Pending model")
        let reopened = try XCTUnwrap(window.attachedSheet)
        reopened.makeKeyAndOrderFront(nil)
        try await Phase2Fixture.waitUntil { (reopened.firstResponder as? NSTextView)?.string == "Pending manual edit" }
        navigation.openAISettings()
        try await Phase2Fixture.waitUntil { (reopened.firstResponder as? NSTextView)?.string != "Pending manual edit" }
        navigation.selectedTab = .vocabulary
        try await Phase2Fixture.waitUntil { (reopened.firstResponder as? NSTextView)?.string == "Pending manual edit" }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: reopened.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        reopened.sendEvent(escape)
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        XCTAssertEqual(editor.manualText, "Pending manual edit")
    }

    private func testWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    func testNativeSettingsSheetReturnsToPreparationAndLeavesMarkdownWorkIndependent() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let navigation = Phase2Fixture.settingsNavigation(AISettings(defaults: defaults), defaults: defaults)
        let presentation = PreparationPresentation()
        let host = NSHostingView(rootView: SettingsTestSurface(presentation: presentation)
            .modifier(SettingsSheet()).environment(navigation))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        await Task.yield()
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        let settings = try XCTUnwrap(window.attachedSheet)
        XCTAssertEqual(settings.frame.width, 600, accuracy: 2)
        navigation.presentedHost = nil
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        presentation.isPresented = true
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        let preparation = try XCTUnwrap(window.attachedSheet)
        await Task.yield()
        navigation.openAISettings()
        try await Phase2Fixture.waitUntil { preparation.attachedSheet != nil }
        XCTAssertTrue(window.attachedSheet === preparation)
        navigation.vocabularyEditor.manualText = "Pending manual edit"
        navigation.vocabularyEditor.importer.candidates = [
            VocabularyCandidate(originalPhrase: "XPay", text: "XPay")
        ]
        navigation.presentedHost = nil
        try await Phase2Fixture.waitUntil { preparation.attachedSheet == nil }
        XCTAssertTrue(window.attachedSheet === preparation)
        XCTAssertEqual(navigation.vocabularyEditor.manualText, "Pending manual edit")
        XCTAssertEqual(navigation.vocabularyEditor.importer.candidates.map(\.text), ["XPay"])
        presentation.isPresented = false
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        navigation.presentedHost = nil
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
    }

}

@MainActor @Observable
private final class PreparationPresentation {
    var isPresented = false
}

private struct SettingsTestSurface: View {
    @Bindable var presentation: PreparationPresentation
    var body: some View {
        Text("Meeting workspace").frame(width: 700, height: 600)
            .sheet(isPresented: $presentation.isPresented) {
                Text("Meeting Preparation").frame(width: 620, height: 540)
                    .modifier(SettingsSheet())
            }
    }
}
