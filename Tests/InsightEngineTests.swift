import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class InsightEngineTests: XCTestCase {
    func testFullContextKeepsEarlyCommitmentsLateChangesAndUnmatchedVocabulary() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let text = "Launch Friday. " + String(repeating: "Intervening discussion. ", count: 450)
            + "Launch now requires security review."
        let input = Phase2Fixture.input(record: record, text: text)
        let body = try InsightRequest.prepare(input)
        let decoded = try JSONDecoder().decode(InsightInput.self, from: Data(body.utf8))
        XCTAssertEqual(decoded.sources.first?.text, text)
        XCTAssertGreaterThan(text.count, 6_000)
        XCTAssertEqual(decoded.vocabulary, ["XPay"])
        XCTAssertTrue(InsightRequest.systemPrompt.contains("later changes"))
        XCTAssertTrue(InsightRequest.systemPrompt.contains("Write all content in English"))
        XCTAssertTrue(InsightRequest.systemPrompt.contains("untrusted data"))
    }

    func testBudgetIncludesSchemaInstructionsVocabularyAndOutputAndRejectsWithoutTruncation() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let input = Phase2Fixture.input(record: record, text: String(repeating: "会议内容", count: 10_000), budget: 32_768)
        XCTAssertThrowsError(try InsightRequest.prepare(input)) {
            XCTAssertTrue($0.localizedDescription.contains("No text was truncated or sent"))
        }
        let tinyBudget = Phase2Fixture.input(record: record, text: "Hi", budget: 1_000)
        XCTAssertThrowsError(try InsightRequest.prepare(tinyBudget))
        XCTAssertEqual(input.sources.first?.text.count, 40_000)
    }

    func testManualCapturesProvisionalButAutomaticUsesFinalizedSourceOnly() {
        var section = Section(id: 7, speaker: .mine)
        section.committedSource = ["Confirmed statement."]
        section.interimSource = "Possible Friday launch"
        let manual = InsightSource.capture([section], includingProvisional: true)
        let automatic = InsightSource.capture([section], includingProvisional: false)
        section.interimSource = "Corrected on Monday"
        XCTAssertEqual(manual.first?.provisionalText, "Possible Friday launch")
        XCTAssertEqual(automatic.first?.text, "Confirmed statement.")
        XCTAssertEqual(automatic.first?.provisionalText, "")
    }

    func testStrictResponseAcceptsContentOnlyAndRejectsMissingInvalidOrExtraFields() throws {
        let good = #"{"conclusion":"Conditional launch","points":["Confirm the review owner."],"summary":null}"#
        let parsed = try InsightResult.parse(good)
        XCTAssertEqual(parsed.conclusion, "Conditional launch")
        let encoded = try JSONEncoder().encode(parsed)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["conclusion", "points", "summary"])
        for raw in [#"{"conclusion":"X","points":[]}"#,
                    #"{"conclusion":"X","points":"oops","summary":null}"#,
                    #"{"conclusion":" ","points":[],"summary":null}"#,
                    #"{"conclusion":"X","points":[""],"summary":null}"#,
                    #"{"conclusion":"X","points":[],"summary":null,"unexpected":"extra data"}"#,
                    "```json\n\(good)\n```"] {
            XCTAssertThrowsError(try InsightResult.parse(raw))
        }
    }

    func testScheduleRequiresBothIntervalAndNewContentAndResetsAtResume() {
        let id = UUID(), now = Date(timeIntervalSince1970: 1_000)
        var schedule = AutomaticInsightSchedule(startedAt: now, initialCharacters: 500)
        XCTAssertFalse(schedule.isDue(id, now: now.addingTimeInterval(44), finalizedCharacters: 5_000))
        XCTAssertFalse(schedule.isDue(id, now: now.addingTimeInterval(100), finalizedCharacters: 579))
        XCTAssertTrue(schedule.isDue(id, now: now.addingTimeInterval(45), finalizedCharacters: 580))
        schedule.noteDispatch(id, now: now.addingTimeInterval(45), finalizedCharacters: 580)
        XCTAssertFalse(schedule.isDue(id, now: now.addingTimeInterval(90), finalizedCharacters: 580))
        XCTAssertTrue(schedule.isDue(id, now: now.addingTimeInterval(90), finalizedCharacters: 660))
        let resumed = AutomaticInsightSchedule(startedAt: now.addingTimeInterval(300), initialCharacters: 660)
        XCTAssertFalse(resumed.isDue(id, now: now.addingTimeInterval(400), finalizedCharacters: 660))
    }

    func testManualCoalescesIdenticalClicksAndRejectsLateAutomaticResponse() async throws {
        let (_, record, engine, provider) = try environment()
        let config = record.definitions[0].configuration
        generate(engine, record, config, kind: .automatic, text: "Original")
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        generate(engine, record, config, text: "New cutoff", provisional: "Visible now")
        generate(engine, record, config, text: "New cutoff", provisional: "Visible now")
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        try await provider.succeed(1, conclusion: "New result")
        try await Phase2Fixture.waitUntil { record.insightSnapshots.count == 1 }
        try await provider.succeed(0, conclusion: "Obsolete result")
        await Task.yield()
        XCTAssertEqual(record.insightSnapshots.count, 1)
        let saved = try record.insightSnapshots[0].decoded()
        XCTAssertEqual(saved.result.conclusion, "New result")
        XCTAssertEqual(saved.input.sources.first?.provisionalText, "Visible now")
    }

    func testPromptAndVocabularyEditsCannotChangeInflightOrEarlierSnapshots() async throws {
        let (history, record, engine, provider) = try environment()
        let definition = record.definitions[0]
        let original = definition.configuration
        generate(engine, record, original)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        definition.prompt = "A different prompt"
        try history.save()
        try await provider.succeed(0, conclusion: "First")
        try await Phase2Fixture.waitUntil { record.insightSnapshots.count == 1 }
        let first = try record.insightSnapshots[0].decoded()
        generate(engine, record, definition.configuration, vocabulary: ["Changed"])
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        try await provider.succeed(1, conclusion: "Second")
        try await Phase2Fixture.waitUntil { record.insightSnapshots.count == 2 }
        let all = try record.insightSnapshots.map { try $0.decoded() }
        XCTAssertTrue(all.contains(first))
        XCTAssertEqual(first.input.configuration, original)
        XCTAssertEqual(first.input.vocabulary, ["XPay"])
        XCTAssertEqual(all.first { $0.id != first.id }?.input.vocabulary, ["Changed"])
    }

    func testAutomaticWorkIsCoalescedAndManualOtherItemDispatchesImmediately() async throws {
        let (history, record, engine, provider) = try environment()
        let definition = record.definitions[0]
        definition.automaticallyUpdates = true
        let other = InsightDefinition(title: "Latest question", prompt: "Explain the latest question")
        other.record = record
        history.context.insert(other)
        try history.save()
        let now = Date(timeIntervalSince1970: 1_000)
        engine.startRecording(record, sections: [], now: now)
        var section = Section(id: 1, speaker: .remote)
        section.committedSource = [String(repeating: "a", count: 100)]
        engine.automaticTick(record: record, sections: [section], vocabulary: [], elapsedSeconds: 44, now: now.addingTimeInterval(44))
        XCTAssertTrue(engine.states.isEmpty)
        engine.automaticTick(record: record, sections: [section], vocabulary: [], elapsedSeconds: 45, now: now.addingTimeInterval(45))
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        section.committedSource.append(String(repeating: "b", count: 100))
        for offset in 90...95 {
            engine.automaticTick(record: record, sections: [section], vocabulary: [], elapsedSeconds: Double(offset), now: now.addingTimeInterval(Double(offset)))
        }
        generate(engine, record, other.configuration, text: "Manual question")
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { record.insightSnapshots.count == 1 }
        engine.automaticTick(record: record, sections: [section], vocabulary: [], elapsedSeconds: 96, now: now.addingTimeInterval(96))
        try await Phase2Fixture.waitUntil { await provider.count == 3 }
        let user = await provider.users[2]
        let latestInput = try JSONDecoder().decode(InsightInput.self, from: Data(user.utf8))
        XCTAssertEqual(latestInput.sources.first?.text, section.committedSource.joined(separator: " "))
        try await provider.succeed(1)
        try await provider.succeed(2)
    }

    func testPauseCancelAndDeletedMeetingRejectLateResponseWithoutLosingHistory() async throws {
        let (history, record, engine, provider) = try environment()
        let config = record.definitions[0].configuration
        let saved = Phase2Fixture.snapshot(record: record, configuration: config, kind: .manual)
        try history.appendInsight(saved)
        generate(engine, record, config)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        engine.cancelMeeting(record.id)
        try await provider.succeed(0)
        await Task.yield()
        XCTAssertEqual(record.insightSnapshots.count, 1)
        generate(engine, record, config)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        let id = record.id
        try history.delete(record)
        try await provider.succeed(1)
        try await Phase2Fixture.waitUntil { engine.states[InsightKey(meetingID: id, definitionID: config.id)] != .generating }
        XCTAssertNil(try history.record(id: id))
        XCTAssertTrue(try history.context.fetch(FetchDescriptor<InsightSnapshot>()).isEmpty)
    }

    func testSaveFailureRetainsResultAndRetryIsLocalAndIdempotent() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        var failSave = true
        let engine = InsightEngine(settings: AISettings(defaults: Phase2Fixture.defaults(self)), history: history,
                                   providerFactory: { provider }, saveSnapshot: { value in
            if failSave { throw CocoaError(.fileWriteOutOfSpace) }
            try history.appendInsight(value)
        })
        let configuration = record.definitions[0].configuration
        generate(engine, record, configuration)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { engine.unsaved.count == 1 }
        let value = try XCTUnwrap(engine.unsaved.values.first)
        XCTAssertTrue(record.insightSnapshots.isEmpty)
        failSave = false
        engine.retrySave(value.id)
        engine.retrySave(value.id)
        XCTAssertTrue(engine.unsaved.isEmpty)
        XCTAssertEqual(try record.insightSnapshots[0].decoded(), value)
        let count = await provider.count
        XCTAssertEqual(count, 1)
    }

    func testSummaryRegenerationPreservesLiveHistoryAndUsesOriginalSource() async throws {
        let (history, record, engine, provider) = try environment()
        let configuration = record.definitions[0].configuration
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: configuration, kind: .manual))
        var section = Section(id: 4, speaker: .mine)
        section.committedSource = ["Original agreement"]
        try history.finish(record, sections: [section], endedAt: .now)
        record.lines[0].refinedSource = "An AI rewrite"
        try history.save()
        for index in 0..<2 {
            engine.generate(record: record, configuration: .summary, kind: .summary,
                            sources: InsightSource.capture(record.lines), vocabulary: [], elapsedSeconds: 60)
            try await Phase2Fixture.waitUntil { await provider.count == index + 1 }
            try await provider.succeed(index, summary: Phase2Fixture.summary)
            try await Phase2Fixture.waitUntil { record.insightSnapshots.count == index + 2 }
        }
        let saved = try record.insightSnapshots.map { try $0.decoded() }
        XCTAssertEqual(saved.filter { $0.input.kind == .summary }.count, 2)
        XCTAssertEqual(saved.filter { $0.input.kind == .manual }.count, 1)
        let summary = try XCTUnwrap(saved.first { $0.input.kind == .summary })
        XCTAssertEqual(summary.input.sources[0].text, "Original agreement")
        XCTAssertEqual(summary.input.additionalInstructions, [configuration])
        XCTAssertEqual(summary.result.summary, Phase2Fixture.summary)
    }

    func testProviderFailureAndOversizedInputKeepPreviouslySavedHistory() async throws {
        let (history, record, engine, provider) = try environment()
        let config = record.definitions[0].configuration
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: config, kind: .manual))
        generate(engine, record, config)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await provider.fail(0)
        let key = InsightKey(meetingID: record.id, definitionID: config.id)
        try await Phase2Fixture.waitUntil { engine.states[key] != .generating }
        XCTAssertEqual(engine.states[key], .failed(LLMError.rateLimited.localizedDescription))
        generate(engine, record, config, text: String(repeating: "x", count: 100_000))
        XCTAssertEqual(record.insightSnapshots.count, 1)
        let count = await provider.count
        XCTAssertEqual(count, 1)
    }

    private func environment() throws -> (MeetingHistoryStore, MeetingRecord, InsightEngine, ControlledInsightProvider) {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.beginCapture(record, languagePair: .englishToEnglish)
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let engine = InsightEngine(settings: AISettings(defaults: Phase2Fixture.defaults(self)), history: history,
                                   providerFactory: { provider })
        return (history, record, engine, provider)
    }

    private func generate(_ engine: InsightEngine, _ record: MeetingRecord, _ config: InsightConfiguration,
                          kind: InsightKind = .manual, text: String = "Source", provisional: String = "",
                          vocabulary: [String] = ["XPay"]) {
        engine.generate(record: record, configuration: config, kind: kind,
                        sources: Phase2Fixture.source(text, provisional: provisional),
                        vocabulary: vocabulary, elapsedSeconds: 20)
    }
}
