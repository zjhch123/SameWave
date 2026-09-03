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
