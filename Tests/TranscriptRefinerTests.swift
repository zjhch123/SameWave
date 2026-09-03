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
            glossary: []
        )

        XCTAssertTrue(prompt.contains("源语言是简体中文，目标语言是英语"))
        XCTAssertTrue(prompt.contains("\"target\":\"英语译文\""))
    }

    func testSameLanguagePromptExplicitlyDisablesTranslation() {
        let prompt = TranscriptRefiner.prompt(
            languagePair: .englishToEnglish,
            glossary: []
        )

        XCTAssertTrue(prompt.contains("源语言和目标语言相同，不要翻译"))
        XCTAssertFalse(prompt.contains("重新翻译"))
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
