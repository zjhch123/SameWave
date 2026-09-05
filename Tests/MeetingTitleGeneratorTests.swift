import XCTest
@testable import 同频

@MainActor
final class MeetingTitleGeneratorTests: XCTestCase {
    func testPromptNamesTitleFieldForPartiallyCompatibleGateways() {
        XCTAssertTrue(MeetingTitleGenerator.systemPrompt().contains("title 字段"))
    }

    func testGenerateUsesIndependentProviderRequestAndParsesTitle() async throws {
        let provider = StubProvider(output: #"{"title":" 项目交付时间与风险讨论 "}"#)

        let title = try await MeetingTitleGenerator.generate(
            lines: [makeLine(index: 0, text: "Let's review the delivery risks")],
            provider: provider
        )

        XCTAssertEqual(title, "项目交付时间与风险讨论")
        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
        let schemaName = await provider.lastSchemaName
        XCTAssertEqual(schemaName, "meeting_title")
    }

    func testParseRejectsBlankTitleAndCapsUnexpectedlyLongOutput() {
        XCTAssertNil(MeetingTitleGenerator.parse(#"{"title":"   "}"#))

        let longTitle = String(repeating: "题", count: 40)
        let parsed = MeetingTitleGenerator.parse(#"{"title":"\#(longTitle)"}"#)

        XCTAssertEqual(parsed?.count, MeetingTitleGenerator.titleCharacterLimit)
    }

    func testInputUsesChronologicalSourceTranscriptWithinBudget() {
        let lines = [
            makeLine(index: 1, text: "second", refinedSource: "refined second"),
            makeLine(index: 0, text: "first")
        ]

        let input = MeetingTitleGenerator.input(lines: lines, limit: 100)

        XCTAssertEqual(input, "对方：first\n对方：second")
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
