import AppKit
import Observation
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class SettingsPresentationTests: XCTestCase {
    func testDismissingSettingsEndsModelLoadingAndKeepsDraft() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        let draft = navigation.aiDraft
        draft.providerID = "custom"
        draft.apiKey = "test-key"
        draft.customAPIAddress = "https://example.com/v1"
        draft.customModel = "retained-model"
        let window = testWindow()
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close() }
        navigation.openSettings()
        try await Phase2Fixture.waitUntil { window.attachedSheet != nil }
        draft.fetchModels {
            try await Task.sleep(for: .seconds(60))
            return []
        }
        XCTAssertEqual(draft.modelDiscoveryState, .loading)
        navigation.presentedHost = nil
        try await Phase2Fixture.waitUntil { window.attachedSheet == nil }
        XCTAssertEqual(draft.modelDiscoveryState, .idle)
        XCTAssertTrue(draft.canFetchModels)
        XCTAssertEqual(draft.customModel, "retained-model")
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
    }

    func testEmbeddedVocabularyKeepsOneSettingsSheetAndIndependentDrafts() async throws {
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
        navigation.aiDraft.customModel = "Pending model"
        navigation.aiDraft.contextBudget = 64_000
        navigation.selectedTab = .vocabulary
        await Task.yield()
        XCTAssertNil(settingsSheet.attachedSheet)
        XCTAssertEqual(settingsSheet.frame.size, initialSize)
        editor.manualText = "XPay"
        editor.addTerms()
        editor.manualText = "Pending manual edit"
        editor.isAddingTerms = true
        editor.focusedField = .manual
        navigation.openAISettings()
        await Task.yield()
        XCTAssertTrue(window.attachedSheet === settingsSheet)
        XCTAssertNil(settingsSheet.attachedSheet)
        XCTAssertEqual(navigation.selectedTab, .ai)
        XCTAssertEqual(navigation.aiDraft.customModel, "Pending model")
        XCTAssertEqual(navigation.aiDraft.contextBudget, 64_000)
        XCTAssertNotEqual(settings.customModel, "Pending model")
        navigation.aiDraft.revert()
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
        XCTAssertFalse(navigation.aiDraft.isDirty)
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
