import XCTest
@testable import SameWave

@MainActor
final class MeetingTitleGeneratorTests: XCTestCase {
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

    init(output: String) {
        self.output = output
    }

    func complete(system: String, user: String,
                  schema: LLMResponseSchema) async throws -> String {
        callCount += 1
        lastSchemaName = schema.name
        return output
    }
}
