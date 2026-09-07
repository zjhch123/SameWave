import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class MeetingRefinementControllerTests: XCTestCase {
    func testSwitchingAndConcurrentMeetingsRetainProgressAndSaveToTheirOwners() async throws {
        let (history, coordinator, settings, provider) = try environment()
        let first = try meeting(history, name: "First", count: 9, needsTitle: true)
        let second = try meeting(history, name: "Second")
        await coordinator.openHistory(first)
        let refinement = try XCTUnwrap(coordinator.refinement(for: first, settings: settings, providerFactory: { provider }))
        refinement.start()
        refinement.start()
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        XCTAssertTrue(refinement.isRefining)
        XCTAssertTrue(refinement.isGeneratingTitle)
        await coordinator.openHistory(second)
        let other = try XCTUnwrap(coordinator.refinement(for: second, settings: settings, providerFactory: { provider }))
        other.start()
        try await Phase2Fixture.waitUntil { await provider.count == 3 }
        XCTAssertTrue(coordinator.backgroundActivity(for: first.id)?.contains("Refining transcript") == true)
        await provider.completeTranscript(containing: "First 0", indices: 0..<8, prefix: "First refined")
        try await Phase2Fixture.waitUntil { refinement.refiner.state == .refining(done: 1, total: 2) }
        await provider.completeTranscript(containing: "Second 0", indices: 0..<1, prefix: "Second refined")
        try await Phase2Fixture.waitUntil { !other.isRefining }
        XCTAssertEqual(second.lines.first?.refinedSource, "Second refined 0")
        XCTAssertEqual(second.lines.first?.refinedTarget, "Second refined 0")
        await coordinator.openHistory(first)
        XCTAssertTrue(coordinator.refinement(for: first, settings: settings) === refinement)
        XCTAssertEqual(refinement.refiner.state, .refining(done: 1, total: 2))
        await coordinator.openHistory(second)
        await provider.completeTitle("First Meeting Title")
        await provider.completeTranscript(containing: "First 8", indices: 8..<9, prefix: "First refined")
        try await Phase2Fixture.waitUntil { !refinement.isRefining && !refinement.isGeneratingTitle }
        XCTAssertNotNil(first.refinedAt)
        XCTAssertEqual(first.aiTitle, "First Meeting Title")
        XCTAssertEqual(first.lines.sorted { $0.orderIndex < $1.orderIndex }.map(\.refinedSource),
                       (0..<9).map { "First refined \($0)" })
        XCTAssertEqual(first.lines.first { $0.orderIndex == 0 }?.sourceText, "First 0")
        XCTAssertNil(coordinator.backgroundActivity(for: first.id))
        XCTAssertEqual(coordinator.workspaceRecord?.id, second.id)
    }

    func testDeletionInvalidatesRefinementAndTitleEvenWhenProviderIgnoresCancellation() async throws {
        let (history, coordinator, settings, provider) = try environment()
        let record = try meeting(history, name: "Deleted", count: 9, needsTitle: true)
        let id = record.id
        await coordinator.openHistory(record)
        let refinement = try XCTUnwrap(coordinator.refinement(for: record, settings: settings, providerFactory: { provider }))
        refinement.start()
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        coordinator.delete(record)
        XCTAssertNil(coordinator.refinements[id])
        XCTAssertFalse(refinement.isRefining)
        await provider.completeTranscript(containing: "Deleted 0", indices: 0..<8, prefix: "Late")
        await provider.completeTitle("Late Title")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(try history.record(id: id))
        XCTAssertTrue(try history.context.fetch(FetchDescriptor<TranscriptLine>()).isEmpty)
        let count = await provider.count
        XCTAssertEqual(count, 2, "Cancellation must prevent dispatching the second batch")
        XCTAssertNil(coordinator.backgroundActivity(for: id))
    }

    func testFailureSurvivesNavigationAndRetryDoesNotAffectAnotherMeeting() async throws {
        let (history, coordinator, settings, provider) = try environment()
        let record = try meeting(history, name: "Retry")
        let other = try meeting(history, name: "Other")
        let refinement = try XCTUnwrap(coordinator.refinement(for: record, settings: settings, providerFactory: { provider }))
        refinement.start()
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await coordinator.openHistory(other)
        await provider.failAll()
        try await Phase2Fixture.waitUntil { !refinement.isRefining }
        XCTAssertEqual(refinement.errorMessage, LLMError.rateLimited.localizedDescription)
        await coordinator.openHistory(record)
        XCTAssertTrue(coordinator.refinements[record.id] === refinement)
        XCTAssertNil(record.refinedAt)
        refinement.start()
        XCTAssertNil(refinement.errorMessage)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await provider.completeTranscript(containing: "Retry 0", indices: 0..<1, prefix: "Recovered")
        try await Phase2Fixture.waitUntil { !refinement.isRefining }
        XCTAssertEqual(record.lines.first?.refinedSource, "Recovered 0")
        XCTAssertNil(other.refinedAt)
    }

    func testUserTitleSavedInAnotherViewRejectsBackgroundTitleWithoutAffectingRefinement() async throws {
        let (history, coordinator, settings, provider) = try environment()
        let record = try meeting(history, name: "User", needsTitle: true)
        let refinement = try XCTUnwrap(coordinator.refinement(for: record, settings: settings, providerFactory: { provider }))
        refinement.start()
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await coordinator.startNewMeeting()
        record.userTitle = "My Saved Title"
        try history.save()
        await provider.completeTitle("Obsolete AI Title")
        await provider.completeTranscript(containing: "User 0", indices: 0..<1, prefix: "Refined")
        try await Phase2Fixture.waitUntil { !refinement.isRefining && !refinement.isGeneratingTitle }
        XCTAssertEqual(record.displayTitle, "My Saved Title")
        XCTAssertNil(record.aiTitle)
        XCTAssertNotNil(record.refinedAt)
        XCTAssertNil(refinement.titleErrorMessage)
    }

    func testFailedBatchPreservesSuccessfulBatchesAndOriginalLines() async throws {
        let (history, coordinator, settings, provider) = try environment()
        let record = try meeting(history, name: "Partial", count: 9)
        let refinement = try XCTUnwrap(coordinator.refinement(for: record, settings: settings, providerFactory: { provider }))
        refinement.start()
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await provider.completeTranscript(containing: "Partial 0", indices: 0..<8, prefix: "Refined")
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await provider.failAll()
        try await Phase2Fixture.waitUntil { !refinement.isRefining }
        XCTAssertNotNil(record.refinedAt)
        XCTAssertEqual(record.lines.filter { $0.refinedSource != nil }.count, 8)
        XCTAssertEqual(record.lines.first { $0.orderIndex == 8 }?.sourceText, "Partial 8")
        XCTAssertNil(record.lines.first { $0.orderIndex == 8 }?.refinedSource)
    }

    func testRefinementSaveFailureRestoresOnlyItsFieldsAndCanBeRetried() throws {
        let history = try Phase2Fixture.history()
        let record = try meeting(history, name: "Original", pair: .englishToSimplifiedChinese)
        let other = try meeting(history, name: "Other")
        other.userTitle = "Unrelated pending edit"
        let data = Data(#"{"i":0,"source":"Corrected","target":"修正"}"#.utf8)
        let line = try JSONDecoder().decode(TranscriptRefiner.RefinedLine.self, from: data)
        let outcome = TranscriptRefiner.Outcome(byIndex: [0: line], glossaryJSON: "[]")
        XCTAssertThrowsError(try history.saveRefinement(outcome, to: record, persist: { _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }))
        XCTAssertNil(record.refinedAt)
        XCTAssertNil(record.lines.first?.refinedSource)
        XCTAssertNil(record.glossaryJSON)
        XCTAssertEqual(other.userTitle, "Unrelated pending edit")
        try history.saveRefinement(outcome, to: record)
        XCTAssertEqual(record.lines.first?.refinedSource, "Corrected")
        XCTAssertEqual(record.lines.first?.refinedTarget, "修正")
        XCTAssertEqual(record.lines.first?.sourceText, "Original 0")
    }

    private func environment() throws -> (MeetingHistoryStore, CaptureCoordinator, AISettings, ControlledRefinementProvider) {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let provider = ControlledRefinementProvider()
        addTeardownBlock { await provider.failAll() }
        return (history, coordinator, settings, provider)
    }

    private func meeting(_ history: MeetingHistoryStore, name: String, count: Int = 1,
                         needsTitle: Bool = false, pair: MeetingLanguagePair = .englishToEnglish) throws -> MeetingRecord {
        let record = try history.createDraft(languagePair: pair)
        record.userTitle = needsTitle ? "" : name
        let sections = (0..<count).map { index in
            var section = Section(id: index, speaker: .remote)
            section.committedSource = ["\(name) \(index)"]
            return section
        }
        try history.finish(record, sections: sections, endedAt: .now)
        return record
    }
}

actor ControlledRefinementProvider: LLMProvider {
    private var requests: [(user: String, schema: String)] = []
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    var count: Int { requests.count }

    func complete(system: String, user: String, schema: LLMResponseSchema) async throws -> String {
        let index = requests.count
        requests.append((user, schema.name))
        // Deliberately ignore cancellation so the app must enforce ownership itself.
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func completeTranscript(containing text: String, indices: Range<Int>, prefix: String) {
        guard let index = pending.keys.sorted().first(where: {
            requests[$0].schema != "meeting_title" && requests[$0].user.contains(text)
        }) else { return }
        let lines = indices.map { "{\"i\":\($0),\"source\":\"\(prefix) \($0)\",\"target\":null}" }.joined(separator: ",")
        pending.removeValue(forKey: index)?.resume(returning: "{\"glossary\":[],\"lines\":[\(lines)]}")
    }

    func completeTitle(_ title: String) {
        guard let index = pending.keys.first(where: { requests[$0].schema == "meeting_title" }) else { return }
        pending.removeValue(forKey: index)?.resume(returning: "{\"title\":\"\(title)\"}")
    }

    func failAll() {
        for continuation in pending.values { continuation.resume(throwing: LLMError.rateLimited) }
        pending.removeAll()
    }
}
