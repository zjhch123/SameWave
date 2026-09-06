import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class MeetingTitleGeneratorTests: XCTestCase {
    func testSavedUserTitleSkipsRequestsAcrossCaptureAndDatabaseReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "meetings.store")
        let provider = StubProvider(output: #"{"title":"Generated Release Review"}"#)
        let id: UUID
        do {
            let history = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
            let record = try history.createDraft(languagePair: .englishToEnglish)
            id = record.id
            record.userTitle = "My Release Review"
            try history.save()
            try history.beginCapture(record, languagePair: .englishToEnglish)
            try history.setStatus(record, .paused)
            try history.beginCapture(record, languagePair: .englishToEnglish)
            var section = Section(id: 1, speaker: .remote)
            section.committedSource = ["Review the release risks."]
            try history.finish(record, sections: [section], endedAt: .now)
            let title = try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider)
            XCTAssertNil(title)
            XCTAssertEqual(record.displayTitle, "My Release Review")
        }
        let reopened = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
        let record = try XCTUnwrap(reopened.record(id: id))
        XCTAssertEqual(record.meetingStatus, .ended)
        XCTAssertEqual(record.userTitle, "My Release Review")
        XCTAssertNil(record.aiTitle)
        let title = try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider)
        XCTAssertNil(title)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 0)
        let unconfigured = MeetingTitleGenerator(settings: AISettings(defaults: Phase2Fixture.defaults(self)))
        let skipped = try await unconfigured.generateIfNeeded(for: record)
        XCTAssertNil(skipped)
    }

    func testBlankTitleGeneratesOnceAndExistingAITitleIsReusedAfterClearingUserTitle() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.userTitle = " \n "
        record.aiTitle = " \n "
        record.lines = [makeLine(index: 0, text: "Review the release risks.")]
        let provider = StubProvider(output: #"{"title":"Generated Release Review"}"#)
        let title = try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider)
        XCTAssertEqual(title, "Generated Release Review")
        record.aiTitle = title
        record.userTitle = "My Title"
        try history.save()
        XCTAssertEqual(record.displayTitle, "My Title")
        record.userTitle = ""
        try history.save()
        XCTAssertEqual(record.displayTitle, "Generated Release Review")
        let repeated = try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider)
        XCTAssertNil(repeated)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testUserTitleSavedDuringGenerationRejectsLateResult() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.lines = [makeLine(index: 0, text: "Review the release risks.")]
        let provider = StubProvider(output: #"{"title":"Generated Release Review"}"#, holdsResponse: true)
        addTeardownBlock { await provider.release() }
        let task = Task { try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider) }
        try await Phase2Fixture.waitUntil { await provider.callCount == 1 }
        record.userTitle = "My Title"
        try history.save()
        await provider.release()
        let title = try await task.value
        XCTAssertNil(title)
        XCTAssertNil(record.aiTitle)
        XCTAssertEqual(record.displayTitle, "My Title")
    }

    func testCancelledTitleRequestRejectsProviderThatIgnoresCancellation() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.lines = [makeLine(index: 0, text: "Review the release risks.")]
        let provider = StubProvider(output: #"{"title":"Generated Release Review"}"#, holdsResponse: true)
        addTeardownBlock { await provider.release() }
        let task = Task { try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider) }
        try await Phase2Fixture.waitUntil { await provider.callCount == 1 }
        task.cancel()
        await provider.release()
        do {
            _ = try await task.value
            XCTFail("Cancelled title must not reach persistence")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(record.aiTitle)
    }

    func testPromptNamesTitleFieldForPartiallyCompatibleGateways() {
        let prompt = MeetingTitleGenerator.systemPrompt()
        XCTAssertTrue(prompt.contains("title field"))
        XCTAssertTrue(prompt.contains("English title"))
        XCTAssertTrue(prompt.contains("3–8 words"))
        XCTAssertTrue(prompt.contains("\(MeetingTitleGenerator.titleCharacterLimit) characters"))
    }

    func testGenerateUsesIndependentProviderRequestAndParsesTitle() async throws {
        let provider = StubProvider(output: #"{"title":" Delivery Timeline and Risks "}"#)

        let title = try await MeetingTitleGenerator.generate(
            lines: [makeLine(index: 0, text: "Let's review the delivery risks")],
            provider: provider
        )

        XCTAssertEqual(title, "Delivery Timeline and Risks")
        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
        let schemaName = await provider.lastSchemaName
        XCTAssertEqual(schemaName, "meeting_title")
    }

    func testParseRejectsBlankTitleAndCapsUnexpectedlyLongOutput() {
        XCTAssertNil(MeetingTitleGenerator.parse(#"{"title":"   "}"#))

        let longTitle = String(repeating: "Title ", count: 20)
        let parsed = MeetingTitleGenerator.parse(#"{"title":"\#(longTitle)"}"#)

        XCTAssertEqual(parsed?.count, MeetingTitleGenerator.titleCharacterLimit)
    }

    func testInputUsesChronologicalSourceTranscriptWithinBudget() {
        let lines = [
            makeLine(index: 1, text: "second", refinedSource: "refined second"),
            makeLine(index: 0, text: "first")
        ]

        let input = MeetingTitleGenerator.input(lines: lines, limit: 100)

        XCTAssertEqual(input, "Other party: first\nOther party: second")
    }

    private func makeLine(
        index: Int,
        text: String,
        refinedSource: String? = nil
    ) -> TranscriptLine {
        TranscriptLine(
            speaker: .remote,
            sourceText: text,
            targetText: "",
            spokenAt: .now,
            orderIndex: index,
            sectionId: index,
            refinedSource: refinedSource
        )
    }
}

private actor StubProvider: LLMProvider {
    private(set) var callCount = 0
    private(set) var lastSchemaName: String?
    let output: String
    let holdsResponse: Bool
    private var pending: CheckedContinuation<Void, Never>?

    init(output: String, holdsResponse: Bool = false) {
        self.output = output
        self.holdsResponse = holdsResponse
    }

    func complete(system: String, user: String,
                  schema: LLMResponseSchema) async throws -> String {
        callCount += 1
        lastSchemaName = schema.name
        if holdsResponse { await withCheckedContinuation { pending = $0 } }
        return output
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}
