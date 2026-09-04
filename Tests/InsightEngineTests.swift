import XCTest
@testable import 同频

@MainActor
final class InsightEngineTests: XCTestCase {
    func testPromptDescribesSchemaFieldsForPartiallyCompatibleGateways() {
        let prompt = InsightEngine.systemPrompt(relevantVocabulary: [])

        for field in ["topic", "suggestions", "answer", "todos", "decisions"] {
            XCTAssertTrue(prompt.contains(field))
        }
        XCTAssertFalse(prompt.contains("用户专有词"))
    }

    func testRelevantVocabularyMatchesCaseInsensitivelyAtAlphanumericBoundaries() {
        let vocabulary = ["PR", "XPay", "Copilot", "Not Mentioned"]

        let matches = InsightEngine.relevantVocabulary(
            from: "We use xpay in this project. The final PR works with COPILOT.",
            configuredVocabulary: vocabulary
        )

        XCTAssertEqual(matches, ["PR", "XPay", "Copilot"])
    }

    func testRelevantVocabularyDoesNotMatchInsideLongerWord() {
        XCTAssertEqual(
            InsightEngine.relevantVocabulary(
                from: "This project is ready.",
                configuredVocabulary: ["PR"]
            ),
            []
        )
    }

    func testPromptIncludesOnlyRelevantVocabularyAndPreventsForcedInsertion() {
        let prompt = InsightEngine.systemPrompt(relevantVocabulary: ["XPay", "PR"])

        XCTAssertTrue(prompt.contains("- XPay"))
        XCTAssertTrue(prompt.contains("- PR"))
        XCTAssertTrue(prompt.contains("精确拼写"))
        XCTAssertTrue(prompt.contains("不得强行植入"))
    }

    func testRecentContextKeepsNewestCompleteLines() {
        let transcript = ["older line", "middle line", "newest line"].joined(separator: "\n")

        let context = InsightEngine.recentContext(from: transcript, limit: 23)

        XCTAssertEqual(context, "middle line\nnewest line")
    }

    func testRecentContextTruncatesSingleOversizedLineFromFront() {
        XCTAssertEqual(
            InsightEngine.recentContext(from: "0123456789", limit: 4),
            "6789"
        )
    }

    func testHistoryTranscriptPrefersRefinedSourceAndFallsBackPerLine() {
        let refinedLine = makeLine(
            index: 1,
            source: "raw second",
            refinedSource: "polished second"
        )
        let fallbackLine = makeLine(
            index: 0,
            source: "raw first",
            refinedSource: "   "
        )

        let transcript = InsightEngine.flatten(
            lines: [refinedLine, fallbackLine],
            preferringRefinedSource: true
        )

        XCTAssertEqual(transcript, "对方：raw first\n对方：polished second")
    }

    func testParsesStrictJSONResponseWithNullAnswer() {
        let raw = #"{"topic":"Roadmap","suggestions":[],"answer":null,"todos":[],"decisions":[]}"#

        XCTAssertEqual(InsightEngine.parse(raw)?.topic, "Roadmap")
    }

    func testRejectsFencedOrIncompleteJSONResponse() {
        let fenced = """
        ```json
        {"topic":"Roadmap","suggestions":[],"answer":null,"todos":[],"decisions":[]}
        ```
        """

        XCTAssertNil(InsightEngine.parse(fenced))
        XCTAssertNil(InsightEngine.parse(
            #"{"topic":"Roadmap","suggestions":[],"answer":null,"todos":[]}"#
        ))
    }

    func testRejectsWrongTypesAndTooManySuggestions() {
        XCTAssertNil(InsightEngine.parse(
            #"{"topic":"Roadmap","suggestions":"ask","answer":null,"todos":[],"decisions":[]}"#
        ))
        XCTAssertNil(InsightEngine.parse(
            #"{"topic":"Roadmap","suggestions":["1","2","3","4"],"answer":null,"todos":[],"decisions":[]}"#
        ))
    }

    func testPersistenceRoundTripKeepsRequiredNullAnswerKey() throws {
        let result = InsightResult(
            topic: "Roadmap",
            suggestions: [],
            answer: nil,
            todos: [],
            decisions: []
        )

        let json = try XCTUnwrap(result.encoded())

        XCTAssertTrue(json.contains(#""answer":null"#))
        XCTAssertEqual(InsightResult.decode(from: json), result)
    }

    private func makeLine(
        index: Int,
        source: String,
        refinedSource: String?
    ) -> TranscriptLine {
        TranscriptLine(
            speaker: .remote,
            sourceText: source,
            targetText: "",
            spokenAt: .now,
            orderIndex: index,
            sectionId: index,
            refinedSource: refinedSource
        )
    }
}
