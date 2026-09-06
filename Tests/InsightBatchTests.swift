import XCTest
@testable import SameWave

@MainActor
final class InsightBatchTests: XCTestCase {
    func testBatchKeepsSixRequestsActiveWithFrozenInputsAndOutOfOrderResults() async throws {
        let (history, record, engine, provider) = try environment(definitionCount: 9)
        let configurations = record.insightReadingOrder.map(\.configuration)
        for configuration in configurations {
            try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: configuration, kind: .manual))
        }
        let now = Date(timeIntervalSince1970: 1_000)
        record.definitions.forEach { $0.automaticallyUpdates = true }
        engine.startRecording(record, sections: [], now: now.addingTimeInterval(-60))
        let sources = Phase2Fixture.source("Frozen source", provisional: "Visible provisional words")
        engine.generateAll(record: record, sources: sources, vocabulary: ["XPay"], elapsedSeconds: 42, now: now)
        engine.generateAll(record: record, sources: sources, vocabulary: ["XPay"], elapsedSeconds: 42, now: now)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        XCTAssertEqual(engine.states.values.filter { $0 == .generating }.count, 6)
        XCTAssertEqual(engine.states.values.filter { $0 == .queued }.count, 3)
        let initialRequests = try await requests(provider)
        XCTAssertEqual(Set(initialRequests.map { $0.configuration.id }), Set(configurations.prefix(6).map(\.id)))
        record.insightReadingOrder.last?.prompt = "Edited after the batch started"
        try history.save()
        var section = Section(id: 1, speaker: .remote)
        section.committedSource = [String(repeating: "Later content ", count: 20)]
        engine.automaticTick(record: record, sections: [section], vocabulary: ["Changed"], elapsedSeconds: 99,
                             now: now.addingTimeInterval(60))

        for (completed, index) in [4, 1, 5, 0, 3, 2, 8, 6, 7].enumerated() {
            try await Phase2Fixture.waitUntil { await provider.count == min(9, completed + 6) }
            try await provider.succeed(index, conclusion: "Result \(index)")
            try await Phase2Fixture.waitUntil { record.insightSnapshots.count == configurations.count + completed + 1 }
            if completed < 8 { XCTAssertEqual(engine.batchMeetingID, record.id) }
        }
        let allRequests = try await requests(provider)
        for input in allRequests {
            XCTAssertEqual(input.configuration, configurations.first { $0.id == input.configuration.id })
            XCTAssertEqual(input.sources, sources)
            XCTAssertEqual(input.vocabulary, ["XPay"])
            XCTAssertEqual(input.requestedAt, now)
            XCTAssertEqual(input.elapsedSeconds, 42)
            XCTAssertEqual(input.kind, .manual)
            XCTAssertTrue(input.additionalInstructions.isEmpty)
        }
        try await Phase2Fixture.waitUntil { engine.batchMeetingID == nil }
        XCTAssertEqual(record.insightSnapshots.count, configurations.count * 2)
        XCTAssertEqual(engine.states.values.filter { $0 == .saved }.count, configurations.count)
        let peakActiveCount = await provider.peakActiveCount
        XCTAssertEqual(peakActiveCount, 6)
        for configuration in configurations {
            XCTAssertEqual(record.insightSnapshots.filter { $0.definitionID == configuration.id }.count, 2)
        }
    }

    func testBatchKeepsTheProviderSelectedAtTheClick() async throws {
        let (history, record, _, originalProvider) = try environment(definitionCount: 8)
        let replacementProvider = ControlledInsightProvider()
        addTeardownBlock { await replacementProvider.releaseAll() }
        var selectedProvider = originalProvider
        let engine = InsightEngine(settings: AISettings(defaults: Phase2Fixture.defaults(self)), history: history,
                                   providerFactory: { selectedProvider })
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await originalProvider.count == 6 }
        selectedProvider = replacementProvider
        for index in record.definitions.indices {
            try await Phase2Fixture.waitUntil { await originalProvider.count >= index + 1 }
            try await originalProvider.succeed(index)
        }
        try await Phase2Fixture.waitUntil { engine.batchMeetingID == nil }
        let replacementCount = await replacementProvider.count
        XCTAssertEqual(replacementCount, 0)
        XCTAssertEqual(record.insightSnapshots.count, record.definitions.count)
    }

    func testFailuresContinueAndUnsavedResultsPreventAnotherBatchUntilSaved() async throws {
        let (history, record, _, provider) = try environment()
        let configurations = record.insightReadingOrder.map(\.configuration)
        var failSave = true
        let engine = InsightEngine(settings: AISettings(defaults: Phase2Fixture.defaults(self)), history: history,
                                   providerFactory: { provider }, saveSnapshot: { value in
            if failSave && value.input.configuration.id == configurations[1].id {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try history.appendInsight(value)
        })
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: configurations[0], kind: .manual))
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await provider.count == 3 }
        await provider.fail(0)
        try await provider.succeed(1)
        try await provider.succeed(2)
        try await Phase2Fixture.waitUntil { engine.batchMeetingID == nil }
        XCTAssertEqual(record.insightSnapshots.count, 2)
        XCTAssertEqual(engine.states[InsightKey(meetingID: record.id, definitionID: configurations[0].id)],
                       .failed(LLMError.rateLimited.localizedDescription))
        XCTAssertEqual(engine.unsaved.count, 1)
        XCTAssertFalse(engine.canGenerateAll(record))
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        let requestCount = await provider.count
        XCTAssertEqual(requestCount, 3)
        failSave = false
        engine.retrySave(try XCTUnwrap(engine.unsaved.keys.first))
        XCTAssertTrue(engine.canGenerateAll(record))
        XCTAssertEqual(record.insightSnapshots.count, 3)
    }

    func testStopClearsPendingWorkAndRejectsLateResponseWithoutLosingSuccesses() async throws {
        let (_, record, engine, provider) = try environment(definitionCount: 8)
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { await provider.count == 7 }
        engine.cancelBatch()
        XCTAssertNil(engine.batchMeetingID)
        XCTAssertEqual(engine.states.values.filter { $0 == .cancelled }.count, 7)
        for index in 1..<7 { try await provider.succeed(index, conclusion: "Late result") }
        await Task.yield()
        XCTAssertEqual(record.insightSnapshots.count, 1)
        let requestCount = await provider.count
        XCTAssertEqual(requestCount, 7)
        XCTAssertTrue(engine.canGenerateAll(record))
    }

    func testNewManualRequestSupersedesParallelBatch() async throws {
        let (_, record, engine, provider) = try environment(definitionCount: 8)
        let definitions = record.insightReadingOrder
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        engine.generate(record: record, configuration: definitions[7].configuration, kind: .manual,
                        sources: Phase2Fixture.source("New manual source"), vocabulary: [], elapsedSeconds: 30)
        try await Phase2Fixture.waitUntil { await provider.count == 7 }
        XCTAssertNil(engine.batchMeetingID)
        for index in 0..<6 { try await provider.succeed(index, conclusion: "Obsolete batch result") }
        try await provider.succeed(6, conclusion: "Manual result")
        try await Phase2Fixture.waitUntil { record.insightSnapshots.count == 1 }
        XCTAssertEqual(try record.insightSnapshots[0].decoded().result.conclusion, "Manual result")
    }

    func testDeletedQueuedDefinitionsAreSkippedWithoutDelayingOtherRequests() async throws {
        let (history, record, engine, provider) = try environment(definitionCount: 8)
        let definitions = record.insightReadingOrder
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 40)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        history.context.delete(definitions[6])
        try history.save()
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { await provider.count == 7 }
        let raw = await provider.users[6]
        let input = try JSONDecoder().decode(InsightInput.self, from: Data(raw.utf8))
        XCTAssertEqual(input.configuration.id, definitions[7].id)
        for index in 1..<7 { try await provider.succeed(index) }
        try await Phase2Fixture.waitUntil { engine.batchMeetingID == nil }
        XCTAssertEqual(record.insightSnapshots.count, 7)
    }

    func testCoordinatorUsesOriginalHistoryAndMeetingSwitchCancelsEntireBatch() async throws {
        let (history, record, engine, provider) = try environment()
        var section = Section(id: 1, speaker: .mine)
        section.committedSource = ["Original agreement"]
        try history.finish(record, sections: [section], endedAt: .now)
        record.lines[0].refinedSource = "AI rewrite"
        try history.save()
        let defaults = Phase2Fixture.defaults(self)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults),
                                             defaults: defaults)
        coordinator.history = history
        coordinator.insights = engine
        coordinator.selectedHistoryRecord = record
        coordinator.generateAllInsights()
        try await Phase2Fixture.waitUntil { await provider.count == 3 }
        let raw = await provider.users[0]
        let input = try JSONDecoder().decode(InsightInput.self, from: Data(raw.utf8))
        XCTAssertEqual(input.sources.first?.text, "Original agreement")
        coordinator.selectedHistoryRecord = try history.createDraft(languagePair: .englishToEnglish)
        XCTAssertNil(engine.batchMeetingID)
        XCTAssertTrue(engine.states.values.allSatisfy { $0 == .cancelled })
        for index in 0..<3 { try await provider.succeed(index) }
        await Task.yield()
        XCTAssertTrue(record.insightSnapshots.isEmpty)
        let requestCount = await provider.count
        XCTAssertEqual(requestCount, 3)
    }

    func testFailuresAndIndividualStopsRefillSlotsWithoutRestartingCancelledItems() async throws {
        let (_, record, engine, provider) = try environment(definitionCount: 9)
        let definitions = record.insightReadingOrder
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        let initialRequests = try await requests(provider)
        await provider.fail(2)
        try await Phase2Fixture.waitUntil { await provider.count == 7 }
        XCTAssertEqual(engine.states.values.filter { $0 == .generating }.count, 6)
        engine.cancel(InsightKey(meetingID: record.id, definitionID: definitions[8].id))
        engine.cancel(InsightKey(meetingID: record.id, definitionID: initialRequests[0].configuration.id))
        try await Phase2Fixture.waitUntil { await provider.count == 8 }
        XCTAssertEqual(engine.states.values.filter { $0 == .generating }.count, 6)
        let allRequests = try await requests(provider)
        XCTAssertFalse(allRequests.contains { $0.configuration.id == definitions[8].id })
        engine.cancelBatch()
        for index in 0..<8 where index != 2 { try await provider.succeed(index) }
        await Task.yield()
        XCTAssertNil(engine.batchMeetingID)
        XCTAssertTrue(record.insightSnapshots.isEmpty)
        XCTAssertFalse(engine.states.values.contains(.generating))
    }

    func testAutomaticRequestSharesTheSixRequestLimitAndCompletionRefillsBatch() async throws {
        let (history, record, engine, provider) = try environment(definitionCount: 7)
        let other = try history.createDraft(languagePair: .englishToEnglish)
        try history.beginCapture(other, languagePair: .englishToEnglish)
        let definition = try XCTUnwrap(other.definitions.first)
        definition.automaticallyUpdates = true
        let now = Date(timeIntervalSince1970: 1_000)
        engine.startRecording(other, sections: [], now: now)
        engine.generate(record: other, configuration: definition.configuration, kind: .automatic,
                        sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20, now: now)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        XCTAssertEqual(engine.states.values.filter { $0 == .queued }.count, 2)
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { await provider.count == 7 }
        var section = Section(id: 1, speaker: .mine)
        section.committedSource = [String(repeating: "New speech ", count: 20)]
        engine.automaticTick(record: other, sections: [section], vocabulary: [], elapsedSeconds: 80,
                             now: now.addingTimeInterval(60))
        for index in 1..<8 {
            try await Phase2Fixture.waitUntil { await provider.count >= index + 1 }
            try await provider.succeed(index)
        }
        try await Phase2Fixture.waitUntil { engine.batchMeetingID == nil }
        let peakActiveCount = await provider.peakActiveCount
        XCTAssertEqual(peakActiveCount, 6)
        XCTAssertEqual(record.insightSnapshots.count, 7)
        XCTAssertEqual(other.insightSnapshots.count, 1)
    }

    private func requests(_ provider: ControlledInsightProvider) async throws -> [InsightInput] {
        try await provider.users.map { try JSONDecoder().decode(InsightInput.self, from: Data($0.utf8)) }
    }

    private func environment(definitionCount: Int = 3) throws -> (MeetingHistoryStore, MeetingRecord, InsightEngine, ControlledInsightProvider) {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.beginCapture(record, languagePair: .englishToEnglish)
        for index in 1..<definitionCount {
            let definition = InsightDefinition(title: "Focus \(index)", prompt: "Review focus \(index)")
            definition.createdAt = record.orderedDefinitions[0].createdAt.addingTimeInterval(Double(index))
            definition.record = record
            history.context.insert(definition)
        }
        try history.save()
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let engine = InsightEngine(settings: AISettings(defaults: Phase2Fixture.defaults(self)), history: history,
                                   providerFactory: { provider })
        return (history, record, engine, provider)
    }
}
