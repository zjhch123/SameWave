import XCTest
@testable import SameWave

@MainActor
final class InsightContextWindowTests: XCTestCase {
    func testDefaultIsOneMillionAndExplicitWindowSurvivesReload() {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        XCTAssertEqual(settings.insightContextTokenBudget, 1_000_000)
        settings.insightContextTokenBudget = 65_536
        XCTAssertEqual(AISettings(defaults: defaults).insightContextTokenBudget, 65_536)
        let draft = AISettingsDraft(settings: settings)
        draft.contextBudget = 128_000
        XCTAssertEqual(settings.insightContextTokenBudget, 65_536)
        draft.revert()
        XCTAssertEqual(draft.contextBudget, 65_536)
    }

    func testSavingLargerWindowRetriesTheCompleteMeetingAndFreezesInflightInput() async throws {
        let settings = AISettings(defaults: Phase2Fixture.defaults(self))
        settings.insightContextTokenBudget = 32_768
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .simplifiedChineseToSimplifiedChinese)
        try history.beginCapture(record, languagePair: .simplifiedChineseToSimplifiedChinese)
        let definition = try XCTUnwrap(record.definitions.first)
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let engine = InsightEngine(settings: settings, history: history, providerFactory: { provider })
        let sources = (0..<97).map { index in
            InsightSource(id: index, speaker: .remote, spokenAt: .now,
                          text: String(repeating: "会议内容", count: 22), provisionalText: "")
        }
        let vocabulary = (0..<273).map { "Project Term \($0)" }
        let key = InsightKey(meetingID: record.id, definitionID: definition.id)
        func generate() {
            engine.generate(record: record, configuration: definition.configuration, kind: .manual,
                            sources: sources, vocabulary: vocabulary, elapsedSeconds: 1_730)
        }

        generate()
        guard case .failed(let message) = engine.states[key] else {
            return XCTFail("The configured 32K window must fail local preflight")
        }
        XCTAssertTrue(message.contains("No text was truncated or sent"))
        XCTAssertFalse(message.contains("service rejected"))
        let rejectedRequestCount = await provider.count
        XCTAssertEqual(rejectedRequestCount, 0)

        let draft = AISettingsDraft(settings: settings)
        draft.contextBudget = 1_000_000
        generate()
        let unsavedRequestCount = await provider.count
        XCTAssertEqual(unsavedRequestCount, 0)
        draft.save()
        generate()
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        let raw = await provider.users[0]
        let input = try JSONDecoder().decode(InsightInput.self, from: Data(raw.utf8))
        XCTAssertEqual(input.contextTokenBudget, 1_000_000)
        XCTAssertEqual(input.sources, sources)
        XCTAssertEqual(input.vocabulary, vocabulary)

        // Saving a smaller window cannot retroactively change an active request.
        draft.contextBudget = 32_768
        draft.save()
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { record.insightSnapshots.count == 1 }
        XCTAssertEqual(try record.insightSnapshots[0].decoded().input, input)
        generate()
        guard case .failed = engine.states[key] else { return XCTFail("New requests must use the saved window") }
        XCTAssertEqual(record.insightSnapshots.count, 1)
        let finalRequestCount = await provider.count
        XCTAssertEqual(finalRequestCount, 1)
    }
}
