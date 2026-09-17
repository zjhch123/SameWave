import XCTest
@testable import SameWave

@MainActor
final class CaptionParagraphTests: XCTestCase {
    func testReportedHistoryFragmentsRenderTogetherAndRefinementPreservesGroups() {
        let fragments = ["I'd now like", "to", "quote from", "A great liberal.",
                         "Democrats.", "A friend of Ted.", "Vladimir Lenin"]
        let lines = fragments.enumerated().map { index, text in
            TranscriptLine(speaker: .remote, sourceText: text, targetText: "",
                           spokenAt: Date(timeIntervalSince1970: Double(index)),
                           orderIndex: index, sectionId: index,
                           refinedSource: text + String(repeating: " refined", count: 40))
        }
        let record = MeetingRecord(startedAt: .now, endedAt: .now, languagePair: .englishToSimplifiedChinese,
                                   lineCount: lines.count, status: .ended, lines: lines)
        let original = HistoryTranscript(record: record)
        let refined = HistoryTranscript(record: record, showRefined: true)
        XCTAssertEqual(original.paragraphs.map(\.sectionIDs), [Array(0..<7)])
        XCTAssertEqual(original.paragraphs, refined.paragraphs)
        XCTAssertEqual(TranscriptText.join(original.displayedSections(in: original.paragraphs[0]).map(\.sourceText)),
                       fragments.joined(separator: " "))
        XCTAssertTrue(refined.displayedSections(in: refined.paragraphs[0])[0].sourceText.contains("refined"))
        XCTAssertEqual(record.lines.map(\.sourceText), fragments)
        XCTAssertEqual(record.lineCount, 7)
    }

    func testParagraphsBoundLengthWithoutMovingExistingUnitsOnCorrectionsOrRetractions() {
        var sections = (0..<7).map { section($0, source: String(repeating: "word ", count: 23).trimmed + ".") }
        var layout = CaptionParagraphLayout()
        layout.update(sections: sections)
        XCTAssertEqual(layout.paragraphs.map(\.sectionIDs), [[0, 1, 2], [3, 4, 5], [6]])
        let grouping = layout.paragraphs
        sections[0].committedSource = ["Short correction."]
        sections[2].targetText = "A longer translation cannot change paragraph membership."
        layout.update(sections: sections)
        XCTAssertEqual(layout.paragraphs, grouping)
        sections.removeAll { $0.id == 0 || $0.id == 4 }
        layout.update(sections: sections)
        XCTAssertEqual(layout.paragraphs.map(\.id), [0, 3, 6])
        XCTAssertEqual(layout.paragraphs.map(\.sectionIDs), [[1, 2], [3, 5], [6]])
        sections.append(section(7, source: "More speech."))
        layout.update(sections: sections)
        XCTAssertEqual(layout.paragraphs.map(\.sectionIDs), [[1, 2], [3, 5], [6, 7]])
    }

    func testSpeakerChangesAndLongGapsStartParagraphs() {
        let sections = [section(0, source: "First."), section(1, source: "Second."),
                        section(2, source: "My reply.", speaker: .mine), section(3, source: "Continue."),
                        section(4, source: "After a pause.", seconds: 23)]
        var layout = CaptionParagraphLayout()
        layout.update(sections: sections)
        XCTAssertEqual(layout.paragraphs.map(\.sectionIDs), [[0, 1], [2], [3], [4]])
    }

    func testEnglishChineseAndPunctuationJoinWithoutInventingWords() {
        XCTAssertEqual(TranscriptText.join(["I'd now like", "to", "quote from"]), "I'd now like to quote from")
        XCTAssertEqual(TranscriptText.join(["现在我想", "来", "引用", "一位伟大的自由派人士。"]),
                       "现在我想来引用一位伟大的自由派人士。")
        XCTAssertEqual(TranscriptText.join(["We agree.", "Please continue."]), "We agree. Please continue.")
        XCTAssertEqual(TranscriptText.join(["Hello", ", everyone."]), "Hello, everyone.")
        XCTAssertEqual(TranscriptText.join(["", "  ", "你好。", "请继续。"]), "你好。请继续。")
        XCTAssertEqual(TranscriptText.join(["检查 SwiftUI", "然后发布。"]), "检查 SwiftUI然后发布。")
    }

    func testChineseParagraphBudgetAndLiveMembershipSurviveGrowingDrafts() {
        var layout = CaptionParagraphLayout()
        layout.update(sections: (0..<5).map { section($0, source: String(repeating: "我们讨论计划", count: 8) + "。") })
        XCTAssertEqual(layout.paragraphs.map(\.sectionIDs), [[0, 1], [2, 3], [4]])
        let store = CaptionStore()
        store.updateSource("A stable sentence.", speaker: .remote, isFinal: true)
        store.updateSource("The draft", speaker: .remote, isFinal: false)
        let first = store.paragraphLayout.paragraphs[0]
        store.updateSource("The draft " + String(repeating: "continues ", count: 60), speaker: .remote, isFinal: false)
        XCTAssertEqual(store.paragraphLayout.paragraphs[0].id, first.id)
        XCTAssertEqual(Array(store.paragraphLayout.paragraphs[0].sectionIDs.prefix(2)), first.sectionIDs)
        XCTAssertGreaterThan(store.paragraphLayout.paragraphs.count, 1)
    }

    func testParagraphWaitsForSentenceEndWithinItsLengthLimit() {
        var layout = CaptionParagraphLayout()
        layout.update(sections: [section(0, source: String(repeating: "word ", count: 40)),
                                 section(1, source: String(repeating: "more ", count: 20)),
                                 section(2, source: "in the face. Next sentence."),
                                 section(3, source: "Another paragraph.")])
        XCTAssertEqual(layout.paragraphs.map(\.sectionIDs), [[0, 1, 2], [3]])
        var unpunctuated = CaptionParagraphLayout()
        unpunctuated.update(sections: (0..<8).map {
            section($0, source: String(repeating: "word ", count: 24))
        })
        XCTAssertEqual(unpunctuated.paragraphs.map(\.sectionIDs), [[0, 1, 2, 3], [4, 5, 6, 7]])
    }

    private func section(_ id: Int, source: String, speaker: Speaker = .remote, seconds: Double? = nil) -> Section {
        var section = Section(id: id, speaker: speaker)
        section.committedSource = [source]
        section.startedAt = Date(timeIntervalSince1970: seconds ?? Double(id))
        return section
    }
}
