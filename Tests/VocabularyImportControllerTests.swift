import AppKit
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class VocabularyImportControllerTests: XCTestCase {
    func testMeetingReviewSurvivesSheetClosureAndAttachmentRemovalDuringExtraction() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let other = try history.createDraft(languagePair: .englishToEnglish)
        let urls = try files(["XPay", "SwiftData"])
        try history.attach([.init(fileName: "source-1.md", content: "XPay"),
                            .init(fileName: "source-2.md", content: "SwiftData")], to: record)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let editor = coordinator.vocabularyEditor(for: record, settings: settings)
        let controller = editor.importer
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#), .held(#"{"phrases":["SwiftData"]}"#)
        ])
        addTeardownBlock { await provider.release() }
        defer { controller.reset() }
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            MeetingVocabularyView(record: record, editor: editor, manageContext: {})
                .environment(navigation))
        controller.start(from: urls, using: provider)
        try await waitUntil { await provider.count == 2 }
        controller.candidates[0].text = "XPay Pro"
        controller.candidates[0].isSelected = false
        window.contentView = nil
        window.close()
        await Task.yield()
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(controller.completedCount, 1)
        for document in record.documents { try history.removeAttachment(document) }
        XCTAssertTrue(record.documents.isEmpty)
        let reopened = coordinator.vocabularyEditor(for: record, settings: settings).importer
        XCTAssertTrue(reopened === controller)
        XCTAssertFalse(coordinator.vocabularyEditor(for: other, settings: settings).importer === controller)
        XCTAssertEqual(reopened.candidates[0].text, "XPay Pro")
        XCTAssertFalse(reopened.candidates[0].isSelected)
        await provider.release()
        try await waitUntil { !reopened.isRunning }
        XCTAssertEqual(reopened.candidates.map(\.text), ["XPay Pro", "SwiftData"])
        reopened.saveSelected()
        XCTAssertEqual(record.confirmedVocabulary, ["SwiftData"])
        XCTAssertTrue(record.documents.isEmpty)
        XCTAssertTrue(other.confirmedVocabulary.isEmpty)
        XCTAssertEqual(reopened.candidates.map(\.text), ["XPay Pro"])
    }

    func testDeletingMeetingCancelsExtractionAndRejectsLateResult() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let meetingID = record.id
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let controller = coordinator.vocabularyEditor(for: record, settings: AISettings(defaults: defaults)).importer
        let provider = ControlledVocabularyProvider([.held(#"{"phrases":["LateResult"]}"#)])
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["LateResult"]), using: provider)
        try await waitUntil { await provider.count == 1 }
        coordinator.delete(record)
        XCTAssertNil(try history.record(id: meetingID))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.requests.isEmpty)
        await provider.release()
        try await waitUntil { await provider.active == 0 }
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertEqual(controller.state, .idle)
    }

    func testMeetingSaveFailureKeepsSelectionAndDoesNotStopGeneration() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let personal = SpeechVocabularySettings(defaults: defaults)
        personal.save([])
        var failSave = true
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: AISettings(defaults: defaults),
            readPhrases: { record.confirmedVocabulary }, replacePhrases: { phrases in
                if failSave { throw CocoaError(.fileWriteOutOfSpace) }
                try history.replaceVocabulary(phrases, in: record)
            })
        let controller = editor.importer
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#), .held(#"{"phrases":["SwiftData"]}"#)
        ])
        defer { controller.reset() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay", "SwiftData"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        controller.saveSelected()
        XCTAssertNotNil(controller.saveError)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(controller.candidates.first?.text, "XPay")
        failSave = false
        controller.saveSelected()
        XCTAssertNil(controller.saveError)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(record.confirmedVocabulary, ["XPay"])
        XCTAssertTrue(personal.phrases.isEmpty)
        await provider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["SwiftData"])
    }

    func testEmbeddedVocabularyKeepsExtractionAcrossTabSwitchAndSettingsClosure() async throws {
        let (_, editor, controller) = makeController()
        editor.manualText = "Uncommitted"
        editor.isAddingTerms = true
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay","SwiftData"]}"#), .held(#"{"phrases":["Later"]}"#)
        ])
        addTeardownBlock { await provider.release() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let defaults = Phase2Fixture.defaults(self)
        let navigation = SettingsNavigation(aiSettings: AISettings(defaults: defaults), vocabularyEditor: editor)
        window.contentViewController = NSHostingController(rootView: Text("Workspace").frame(width: 600, height: 540)
            .modifier(SettingsSheet()).environment(navigation))
        defer { window.close(); controller.reset() }
        window.orderFront(nil)
        navigation.selectedTab = .vocabulary
        navigation.openSettings()
        try await waitUntil { window.attachedSheet != nil }
        let settingsSheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertNil(settingsSheet.attachedSheet)
        let host = try XCTUnwrap(settingsSheet.contentView)
        controller.start(from: try files(["XPay SwiftData", "Later"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(controller.candidates.count, 2)

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Markdown incremental review"
        attachment.lifetime = .keepAlways
        add(attachment)

        navigation.openAISettings()
        await Task.yield()
        XCTAssertNil(settingsSheet.attachedSheet)
        XCTAssertTrue(window.attachedSheet === settingsSheet)
        XCTAssertTrue(controller.isRunning)
        navigation.presentedHost = nil
        try await waitUntil { window.attachedSheet == nil }
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(editor.manualText, "Uncommitted")
        XCTAssertEqual(controller.candidates.count, 2)
        await provider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay", "SwiftData", "Later"])
        navigation.openSettings()
        try await waitUntil { window.attachedSheet != nil }
        let reopened = try XCTUnwrap(window.attachedSheet)
        XCTAssertNil(reopened.attachedSheet)
        navigation.selectedTab = .vocabulary
        await Task.yield()
        XCTAssertTrue(window.attachedSheet === reopened)
        XCTAssertNil(reopened.attachedSheet)
        XCTAssertEqual(editor.manualText, "Uncommitted")
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay", "SwiftData", "Later"])
        navigation.presentedHost = nil
        try await waitUntil { window.attachedSheet == nil }
    }

    func testProgressiveReviewPreservesEditsSelectionsAndIdentityAcrossDuplicateTerms() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#),
            .held(#"{"phrases":["xpay","SwiftData"]}"#),
        ])
        defer { controller.reset() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay", "XPay SwiftData"]), using: provider)
        try await waitUntil { await provider.count == 2 }

        XCTAssertEqual(controller.state, .generating)
        XCTAssertEqual(controller.completedCount, 1)
        XCTAssertEqual(controller.currentAttempt, VocabularyAttempt(batchNumber: 2, number: 1))
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay"])
        let originalID = controller.candidates[0].id
        controller.candidates[0].text = "XPay Pro"
        controller.candidates[0].isSelected = false
        await provider.release()
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.candidates.map(\.text), ["XPay Pro", "SwiftData"])
        XCTAssertEqual(controller.candidates[0].id, originalID)
        XCTAssertFalse(controller.candidates[0].isSelected)
        XCTAssertEqual(controller.discoveredCount, 2)
        XCTAssertNil(controller.currentAttempt)
    }

    func testStopKeepsResultsAndRetryWaitsForCancellationThenSkipsSuccess() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#),
            .held(#"{"phrases":["LateResult"]}"#),
            .content(#"{"phrases":["RetryWord"]}"#),
            .content(#"{"phrases":["LastWord"]}"#),
        ])
        defer { controller.reset() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay", "RetryWord", "LastWord"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        controller.candidates[0].text = "Edited"
        controller.candidates[0].isSelected = false
        controller.stop()

        XCTAssertEqual(controller.state, .reviewing)
        XCTAssertEqual(controller.incompleteCount, 2)
        XCTAssertNil(controller.currentAttempt)
        controller.retryIncomplete()
        await Task.yield()
        let beforeRelease = await provider.count
        XCTAssertEqual(beforeRelease, 2)
        await provider.release()
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.candidates.map(\.text), ["Edited", "RetryWord", "LastWord"])
        XCTAssertFalse(controller.candidates[0].isSelected)
        let bodies = await provider.requestBodies
        XCTAssertEqual(bodies.count, 4)
        XCTAssertEqual(bodies[1], bodies[2])
        XCTAssertNil(controller.currentAttempt)
        XCTAssertEqual(controller.incompleteCount, 0)
        let maxActive = await provider.maximumActive
        XCTAssertEqual(maxActive, 1)
    }

    func testFailedRequestDoesNotBlockLaterResultsAndOnlyFailureIsRetried() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#),
            .failure, .failure, .failure,
            .content(#"{"phrases":["SwiftData"]}"#),
            .content(#"{"phrases":["Recovered"]}"#),
        ])
        defer { controller.reset() }
        controller.start(from: try files(["XPay", "Recovered", "SwiftData"]), using: provider)
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.incompleteCount, 1)
        XCTAssertEqual(controller.completedCount, 3)
        XCTAssertEqual(controller.generationError, LLMError.server(503).localizedDescription)
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay", "SwiftData"])
        controller.candidates[0].text = "Edited"
        controller.selectAll(false)
        controller.retryIncomplete()
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.candidates.map(\.text), ["Edited", "SwiftData", "Recovered"])
        XCTAssertFalse(controller.candidates[0].isSelected)
        XCTAssertFalse(controller.candidates[1].isSelected)
        let bodies = await provider.requestBodies
        XCTAssertEqual(bodies.count, 6)
        XCTAssertEqual(bodies[1], bodies[5])
        XCTAssertNil(controller.generationError)
        XCTAssertEqual(controller.incompleteCount, 0)
    }

    func testAllFailuresRemainRetryableWithoutReselectingFiles() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .failure, .failure, .failure, .held(#"{"phrases":["Recovered"]}"#)
        ])
        defer { controller.reset() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["Recovered"]), using: provider)
        try await waitUntil { !controller.isRunning }
        XCTAssertTrue(controller.canRetry)
        XCTAssertEqual(controller.incompleteCount, 1)
        XCTAssertEqual(controller.generationError, LLMError.server(503).localizedDescription)
        XCTAssertNil(controller.currentAttempt)
        let count = await provider.count
        XCTAssertEqual(count, 3)
        controller.retryIncomplete()
        try await waitUntil { await provider.count == 4 }
        XCTAssertEqual(controller.currentAttempt, VocabularyAttempt(batchNumber: 1, number: 1))
        XCTAssertNil(controller.generationError)
        await provider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["Recovered"])
        XCTAssertFalse(controller.canRetry)
        XCTAssertNil(controller.currentAttempt)
    }

    func testStopBeforeFirstResultReturnsToSelectionAndRetainsIncompleteWork() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([.held(#"{"phrases":["Late"]}"#)])
        defer { controller.reset() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["Late"]), using: provider)
        try await waitUntil { await provider.count == 1 }
        controller.stop()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.canRetry)
        XCTAssertTrue(controller.candidates.isEmpty)
        await provider.release()
        try await waitUntil { await provider.active == 0 }
        XCTAssertTrue(controller.candidates.isEmpty)
    }

    func testResetDiscardsReviewAndLateResponsesCannotLeakIntoNewRun() async throws {
        let (settings, _, controller) = makeController()
        let oldProvider = ControlledVocabularyProvider([
            .content(#"{"phrases":["Unsaved"]}"#), .held(#"{"phrases":["Late"]}"#)
        ])
        let newProvider = ControlledVocabularyProvider([.content(#"{"phrases":["Fresh"]}"#)])
        defer { controller.reset() }
        addTeardownBlock { await oldProvider.release() }
        controller.start(from: try files(["Unsaved", "Late"]), using: oldProvider)
        try await waitUntil { await oldProvider.count == 2 }
        controller.reset()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertTrue(controller.requests.isEmpty)
        XCTAssertNil(controller.currentAttempt)
        XCTAssertTrue(settings.phrases.isEmpty)

        controller.start(from: try files(["Fresh"]), using: newProvider)
        await oldProvider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["Fresh"])
        XCTAssertEqual(controller.requests.count, 1)
        XCTAssertNil(controller.currentAttempt)
    }

    func testSaveDuringGenerationPersistsSelectedOnlyWithoutSavingManualDraft() async throws {
        let (settings, editor, controller) = makeController(saved: ["Existing", "Deleted"])
        editor.manualText = "Existing\nManual"
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["Existing","Deleted","XPay","SwiftData"]}"#),
            .held(#"{"phrases":["XPay","More"]}"#),
        ])
        defer { controller.reset() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay SwiftData", "XPay More"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay", "SwiftData"])
        controller.candidates[1].isSelected = false
        controller.saveSelected()

        XCTAssertEqual(settings.phrases, ["Existing", "Deleted", "XPay"])
        XCTAssertEqual(editor.manualText, "Existing\nManual")
        XCTAssertEqual(controller.candidates.map(\.text), ["SwiftData"])
        XCTAssertEqual(controller.savedMessage, "New terms saved: 1")
        XCTAssertTrue(controller.isRunning)
        await provider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["SwiftData", "More"])
        XCTAssertFalse(controller.candidates[0].isSelected)
        controller.reset()
        XCTAssertEqual(editor.manualText, "Existing\nManual")
        XCTAssertEqual(settings.phrases, ["Existing", "Deleted", "XPay"])
    }

    func testEditedDuplicatesAndManualSaveAreDeduplicatedAgain() async throws {
        let (settings, editor, controller) = makeController()
        let provider = ControlledVocabularyProvider([.content(#"{"phrases":["XPay","SwiftData"]}"#)])
        defer { controller.reset() }
        controller.start(from: try files(["XPay SwiftData"]), using: provider)
        try await waitUntil { !controller.isRunning }
        controller.candidates[1].text = " xpay "
        XCTAssertEqual(controller.candidates.first?.text, "XPay")
        editor.manualText = "XPay"
        editor.addTerms()
        controller.saveSelected()
        XCTAssertEqual(settings.phrases, ["XPay"])
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertEqual(controller.savedMessage, "All selected terms already exist; no duplicates were added")
    }

    func testInvalidEditedSelectionCannotBeSaved() async throws {
        let (settings, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([.content(#"{"phrases":["XPay"]}"#)])
        defer { controller.reset() }
        controller.start(from: try files(["XPay"]), using: provider)
        try await waitUntil { !controller.isRunning }
        controller.candidates[0].text = "first\nsecond"
        XCTAssertTrue(controller.hasInvalidSelection)
        controller.saveSelected()
        XCTAssertTrue(settings.phrases.isEmpty)
        XCTAssertEqual(controller.candidates.count, 1)
    }

    private func makeController(saved: [String] = [])
        -> (SpeechVocabularySettings, VocabularyEditorStore, VocabularyImportController) {
        let suite = "VocabularyImportControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = SpeechVocabularySettings(defaults: defaults)
        settings.save(saved)
        let editor = VocabularyEditorStore(aiSettings: AISettings(defaults: defaults), settings: settings)
        return (settings, editor, editor.importer)
    }

    private func files(_ prefixes: [String]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appending(path: "VocabularyImport-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try prefixes.enumerated().map { index, prefix in
            let url = directory.appending(path: "source-\(index + 1).md")
            let text = prefix + " " + String(repeating: "a", count: 17_999 - prefix.count)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "VocabularyImportTests.Timeout", code: 1)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

actor ControlledVocabularyProvider: LLMProvider {
    enum Response: Sendable {
        case content(String), held(String), failure
    }
    let responses: [Response]
    private(set) var count = 0
    private(set) var active = 0
    private(set) var maximumActive = 0
    private(set) var requestBodies: [String] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ responses: [Response]) { self.responses = responses }

    func complete(system: String, user: String, schema: LLMResponseSchema) async throws -> String {
        requestBodies.append(user)
        let index = count
        count += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        guard index < responses.count else { throw LLMError.badResponse }
        switch responses[index] {
        case .content(let text): return text
        case .failure: throw LLMError.server(503)
        case .held(let text):
            // Intentionally ignores cancellation to exercise late-result isolation.
            await withCheckedContinuation { continuation = $0 }
            return text
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
