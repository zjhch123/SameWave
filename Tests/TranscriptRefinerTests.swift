import XCTest
@testable import 同频

@MainActor
final class TranscriptRefinerTests: XCTestCase {
    func testBatchingHonorsLineLimit() {
        let lines = (0..<5).map { makeLine(index: $0, text: "x") }

        let batches = TranscriptRefiner.makeBatches(
            lines,
            maxLines: 2,
            maxCharacters: 100
        )

        XCTAssertEqual(batches.map(\.count), [2, 2, 1])
    }

    func testBatchingStartsNewBatchBeforeCharacterLimitIsExceeded() {
        let lines = [
            makeLine(index: 0, text: "abc"),
            makeLine(index: 1, text: "def")
        ]

        let batches = TranscriptRefiner.makeBatches(
            lines,
            maxLines: 8,
            maxCharacters: 5
        )

        XCTAssertEqual(batches.map(\.count), [1, 1])
    }

    func testTranslationPromptUsesSelectedDirection() {
        let prompt = TranscriptRefiner.prompt(
            languagePair: .simplifiedChineseToEnglish,
            configuredVocabulary: ["XPay", "M365 Copilot"],
            glossary: []
        )

        XCTAssertTrue(prompt.contains("源语言是简体中文，目标语言是英语"))
        XCTAssertTrue(prompt.contains("target 必须使用英语"))
        XCTAssertTrue(prompt.contains("JSON 对象"))
        XCTAssertTrue(prompt.contains("glossary"))
        XCTAssertTrue(prompt.contains("lines"))
        XCTAssertTrue(prompt.contains("- XPay"))
        XCTAssertTrue(prompt.contains("- M365 Copilot"))
        XCTAssertTrue(prompt.contains("不得强行植入未出现的词"))
    }

    func testSameLanguagePromptExplicitlyDisablesTranslation() {
        let prompt = TranscriptRefiner.prompt(
            languagePair: .englishToEnglish,
            configuredVocabulary: [],
            glossary: []
        )

        XCTAssertTrue(prompt.contains("源语言和目标语言相同，不要翻译"))
        XCTAssertTrue(prompt.contains("target 返回 null"))
        XCTAssertFalse(prompt.contains("重新翻译"))
        XCTAssertTrue(prompt.contains("（暂无用户词表）"))
    }

    func testDecodedLineStripsEchoedSpeakerPrefixes() throws {
        let data = try XCTUnwrap(
            #"{"i":3,"source":" 对方： 不。","target":"Other party: No."}"#
                .data(using: .utf8)
        )

        let line = try JSONDecoder().decode(TranscriptRefiner.RefinedLine.self, from: data)

        XCTAssertEqual(line.source, "不。")
        XCTAssertEqual(line.target, "No.")
    }

    func testSpeakerPrefixCleanupDoesNotStripOrdinaryFirstPersonText() {
        XCTAssertEqual(
            TranscriptRefiner.strippingSpeakerPrefix(from: "我觉得这个方案可行。"),
            "我觉得这个方案可行。"
        )
        XCTAssertEqual(
            TranscriptRefiner.strippingSpeakerPrefix(from: "Me too."),
            "Me too."
        )
    }

    func testResponseSchemaFixesTargetTypeForEachMode() throws {
        XCTAssertEqual(
            try targetType(in: TranscriptRefiner.responseSchema(needsTranslation: true)),
            "string"
        )
        XCTAssertEqual(
            try targetType(in: TranscriptRefiner.responseSchema(needsTranslation: false)),
            "null"
        )
    }

    private func targetType(in schema: LLMResponseSchema) throws -> String {
        let data = try OpenAICompatibleProvider.makeRequestBody(
            model: "test-model",
            system: "system",
            user: "user",
            temperature: 0.3,
            schema: schema
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        let root = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(root["properties"] as? [String: Any])
        let lines = try XCTUnwrap(properties["lines"] as? [String: Any])
        let items = try XCTUnwrap(lines["items"] as? [String: Any])
        let lineProperties = try XCTUnwrap(items["properties"] as? [String: Any])
        let target = try XCTUnwrap(lineProperties["target"] as? [String: Any])
        return try XCTUnwrap(target["type"] as? String)
    }

    private func makeLine(index: Int, text: String) -> TranscriptLine {
        TranscriptLine(
            speaker: .remote,
            sourceText: text,
            targetText: "",
            spokenAt: .now,
            orderIndex: index,
            sectionId: index
        )
    }
}
