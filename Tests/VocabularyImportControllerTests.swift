import AppKit
import SwiftUI
import XCTest
@testable import 同频

@MainActor
final class VocabularyImportControllerTests: XCTestCase {
    func testNativeWindowHideKeepsWorkAndCloseCancelsAndDiscards() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay","SwiftData"]}"#), .held(#"{"phrases":["Later"]}"#)
        ])
        addTeardownBlock { await provider.release() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: VocabularyImportWindow(controller: controller)
            .background(Color(nsColor: .windowBackgroundColor)))
        window.contentView = host
        defer { window.close(); controller.close() }
        controller.start(from: try files(["XPay SwiftData", "Later"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        host.layoutSubtreeIfNeeded()
        window.orderOut(nil)
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

        window.close()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertTrue(controller.requests.isEmpty)
        await provider.release()
    }

    func testProgressiveReviewPreservesEditsSelectionsAndMergesLocalSources() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#),
            .held(#"{"phrases":["xpay","SwiftData"]}"#),
        ])
        defer { controller.close() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay", "XPay SwiftData"]), using: provider)
        try await waitUntil { await provider.count == 2 }

        XCTAssertEqual(controller.state, .generating)
        XCTAssertEqual(controller.completedCount, 1)
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay"])
        let originalID = controller.candidates[0].id
        controller.candidates[0].text = "XPay Pro"
        controller.candidates[0].isSelected = false
        await provider.release()
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.candidates.map(\.text), ["XPay Pro", "SwiftData"])
        XCTAssertEqual(controller.candidates[0].id, originalID)
        XCTAssertFalse(controller.candidates[0].isSelected)
        XCTAssertEqual(controller.candidates[0].sources.map(\.fileName), ["source-1.md", "source-2.md"])
        XCTAssertEqual(controller.discoveredCount, 2)
    }

    func testStopKeepsResultsAndRetryWaitsForCancellationThenSkipsSuccess() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay"]}"#),
            .held(#"{"phrases":["LateResult"]}"#),
            .content(#"{"phrases":["RetryWord"]}"#),
            .content(#"{"phrases":["LastWord"]}"#),
        ])
        defer { controller.close() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay", "RetryWord", "LastWord"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        controller.candidates[0].text = "Edited"
        controller.candidates[0].isSelected = false
        controller.stop()

        XCTAssertEqual(controller.state, .reviewing)
        XCTAssertEqual(controller.incompleteCount, 2)
        XCTAssertEqual(controller.attempts.last?.outcome, .cancelled)
        XCTAssertNotNil(controller.attempts.last?.duration)
        controller.retryIncomplete()
        await Task.yield()
        let beforeRelease = await provider.count
        XCTAssertEqual(beforeRelease, 2)
        await provider.release()
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.candidates.map(\.text), ["Edited", "RetryWord", "LastWord"])
        XCTAssertFalse(controller.candidates[0].isSelected)
        XCTAssertEqual(controller.attempts.map(\.batchNumber), [1, 2, 2, 3])
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
        defer { controller.close() }
        controller.start(from: try files(["XPay", "Recovered", "SwiftData"]), using: provider)
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.failedCount, 1)
        XCTAssertEqual(controller.completedCount, 3)
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay", "SwiftData"])
        controller.candidates[0].text = "Edited"
        controller.selectAll(false)
        controller.retryIncomplete()
        try await waitUntil { !controller.isRunning }

        XCTAssertEqual(controller.candidates.map(\.text), ["Edited", "SwiftData", "Recovered"])
        XCTAssertFalse(controller.candidates[0].isSelected)
        XCTAssertFalse(controller.candidates[1].isSelected)
        XCTAssertEqual(controller.attempts.map(\.batchNumber), [1, 2, 2, 2, 3, 2])
        XCTAssertEqual(controller.failedCount, 0)
    }

    func testAllFailuresRemainRetryableWithoutReselectingFiles() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([
            .failure, .failure, .failure, .content(#"{"phrases":["Recovered"]}"#)
        ])
        defer { controller.close() }
        controller.start(from: try files(["Recovered"]), using: provider)
        try await waitUntil { !controller.isRunning }
        XCTAssertTrue(controller.canRetry)
        XCTAssertEqual(controller.failedCount, 1)
        XCTAssertEqual(controller.attempts.map(\.number), [1, 2, 3])
        controller.retryIncomplete()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["Recovered"])
        XCTAssertFalse(controller.canRetry)
    }

    func testStopBeforeFirstResultReturnsToSelectionAndRetainsIncompleteWork() async throws {
        let (_, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([.held(#"{"phrases":["Late"]}"#)])
        defer { controller.close() }
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

    func testCloseDiscardsReviewAndLateResponsesCannotLeakIntoNewRun() async throws {
        let (settings, _, controller) = makeController()
        let oldProvider = ControlledVocabularyProvider([
            .content(#"{"phrases":["Unsaved"]}"#), .held(#"{"phrases":["Late"]}"#)
        ])
        let newProvider = ControlledVocabularyProvider([.content(#"{"phrases":["Fresh"]}"#)])
        defer { controller.close() }
        addTeardownBlock { await oldProvider.release() }
        controller.start(from: try files(["Unsaved", "Late"]), using: oldProvider)
        try await waitUntil { await oldProvider.count == 2 }
        controller.close()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertTrue(controller.requests.isEmpty)
        XCTAssertTrue(controller.attempts.isEmpty)
        XCTAssertFalse(controller.hasActiveWorkflow)
        XCTAssertTrue(settings.phrases.isEmpty)

        controller.start(from: try files(["Fresh"]), using: newProvider)
        await oldProvider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["Fresh"])
        XCTAssertEqual(controller.attempts.count, 1)
    }

    func testSaveDuringGenerationPersistsSelectedOnlyWithoutSavingManualDraft() async throws {
        let (settings, draft, controller) = makeController(saved: ["Existing", "Deleted"])
        draft.text = "Existing\nManual"
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["Existing","Deleted","Manual","XPay","SwiftData"]}"#),
            .held(#"{"phrases":["XPay","More"]}"#),
        ])
        defer { controller.close() }
        addTeardownBlock { await provider.release() }
        controller.start(from: try files(["XPay SwiftData", "XPay More"]), using: provider)
        try await waitUntil { await provider.count == 2 }
        XCTAssertEqual(controller.candidates.map(\.text), ["XPay", "SwiftData"])
        controller.candidates[1].isSelected = false
        controller.saveSelected()

        XCTAssertEqual(settings.phrases, ["Existing", "Deleted", "XPay"])
        XCTAssertEqual(draft.phrases, ["Existing", "Manual", "XPay"])
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(controller.candidates.map(\.text), ["SwiftData"])
        XCTAssertEqual(controller.savedMessage, "已保存 1 个新词")
        XCTAssertTrue(controller.isRunning)
        await provider.release()
        try await waitUntil { !controller.isRunning }
        XCTAssertEqual(controller.candidates.map(\.text), ["SwiftData", "More"])
        XCTAssertFalse(controller.candidates[0].isSelected)
        controller.close()
        draft.revert()
        XCTAssertEqual(draft.phrases, ["Existing", "Deleted", "XPay"])
    }

    func testEditedDuplicatesAndConcurrentSettingsSaveAreDeduplicatedAgain() async throws {
        let (settings, draft, controller) = makeController()
        let provider = ControlledVocabularyProvider([.content(#"{"phrases":["XPay","SwiftData"]}"#)])
        defer { controller.close() }
        controller.start(from: try files(["XPay SwiftData"]), using: provider)
        try await waitUntil { !controller.isRunning }
        controller.candidates[1].text = " xpay "
        XCTAssertEqual(controller.selectedPhrases, ["XPay"])
        draft.text = "XPay"
        draft.save()
        XCTAssertTrue(controller.selectedPhrases.isEmpty)
        controller.saveSelected()
        XCTAssertEqual(settings.phrases, ["XPay"])
        XCTAssertTrue(controller.candidates.isEmpty)
        XCTAssertEqual(controller.savedMessage, "所选词条已存在，没有重复添加")
    }

    func testInvalidEditedSelectionCannotBeSaved() async throws {
        let (settings, _, controller) = makeController()
        let provider = ControlledVocabularyProvider([.content(#"{"phrases":["XPay"]}"#)])
        defer { controller.close() }
        controller.start(from: try files(["XPay"]), using: provider)
        try await waitUntil { !controller.isRunning }
        controller.candidates[0].text = "first\nsecond"
        XCTAssertTrue(controller.hasInvalidSelection)
        controller.saveSelected()
        XCTAssertTrue(settings.phrases.isEmpty)
        XCTAssertEqual(controller.candidates.count, 1)
    }

    private func makeController(saved: [String] = [])
        -> (SpeechVocabularySettings, SpeechVocabularyDraft, VocabularyImportController) {
        let suite = "VocabularyImportControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = SpeechVocabularySettings(defaults: defaults)
        settings.save(saved)
        let draft = SpeechVocabularyDraft(settings: settings)
        return (settings, draft, VocabularyImportController(insightSettings: InsightSettings(), vocabularyDraft: draft))
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

private actor ControlledVocabularyProvider: InsightProvider {
    enum Response: Sendable {
        case content(String), held(String), failure
    }
    let responses: [Response]
    private(set) var count = 0
    private(set) var active = 0
    private(set) var maximumActive = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ responses: [Response]) { self.responses = responses }

    func complete(system: String, user: String, schema: LLMResponseSchema) async throws -> String {
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
