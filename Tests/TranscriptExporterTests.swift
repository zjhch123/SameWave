import XCTest
@testable import SameWave

@MainActor
final class TranscriptExporterTests: XCTestCase {
    func testExportsEnglishTemplatesWhilePreservingAllFourLanguagePairs() {
        for source in MeetingLanguage.allCases {
            for target in MeetingLanguage.allCases {
                let pair = MeetingLanguagePair(source: source, target: target)
                let sourceText = source == .english ? "Let's review the plan." : "我们来讨论计划。"
                let targetText = target == .english ? "Let's review the plan." : "我们来讨论计划。"
                let store = CaptionStore()
                let result = store.appendCommitted(sourceText, speaker: .remote)
                let generation = store.beginTranslation(id: result.sectionId)
                store.applyTranslation(targetText, id: result.sectionId, generation: generation, final: true)

                let markdown = TranscriptExporter.markdown(store: store, showsSourceEcho: pair.needsTranslation)

                XCTAssertTrue(markdown.hasPrefix("# Meeting Transcript\n"))
                XCTAssertTrue(markdown.contains("Generated locally by SameWave · Sections: 1"))
                XCTAssertTrue(markdown.contains("**1. Other party:** \(targetText)"))
                XCTAssertEqual(markdown.components(separatedBy: sourceText).count - 1, 1)
                XCTAssertEqual(markdown.contains("> \(sourceText)"), pair.needsTranslation)
            }
        }
    }

    func testHistoryExportUsesEnglishInsightLabelsAndKeepsRefinedContent() throws {
        let now = Date()
        let line = TranscriptLine(speaker: .mine, sourceText: "原始内容", targetText: "Original content",
                                  spokenAt: now, orderIndex: 0, sectionId: 0,
                                  refinedSource: "整理后的内容", refinedTarget: "Refined content")
        let record = MeetingRecord(startedAt: now, endedAt: now.addingTimeInterval(65),
                                   languagePair: .simplifiedChineseToEnglish, lineCount: 1, status: .ended,
                                   refinedAt: now, lines: [line])
        let insight = InsightResult(conclusion: "Delivery", points: [], summary: Phase2Fixture.summary)
        let input = InsightInput(meetingID: record.id, configuration: .summary, kind: .summary,
                                 requestedAt: now, elapsedSeconds: 65,
                                 sources: InsightSource.capture(record.lines), vocabulary: [],
                                 additionalInstructions: [], providerModel: "Test", contextTokenBudget: 32_768)
        record.insightSnapshots = [try InsightSnapshot(InsightSnapshotValue(
            id: UUID(), input: input, completedAt: now, result: insight))]

        let markdown = TranscriptExporter.markdown(record: record)

        XCTAssertTrue(markdown.contains("## AI Insight History"))
        XCTAssertTrue(markdown.contains("Meeting Insights"))
        XCTAssertTrue(markdown.contains("1m 5s · AI-refined"))
        XCTAssertTrue(markdown.contains("Me:** Refined content"))
        XCTAssertTrue(markdown.contains("> 整理后的内容"))
        for part in Phase2Fixture.summary.parts {
            XCTAssertTrue(markdown.contains("#### \(part.title)"))
            for item in part.items { XCTAssertTrue(markdown.contains("- \(item)")) }
        }
        XCTAssertFalse(markdown.contains("原始内容"))
        XCTAssertEqual(line.sourceText, "原始内容")
    }

    func testHistoryMetadataUsesEnglishDateAndDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DateFormat.dayTime.timeZone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 7,
                                                                    hour: 18, minute: 27)))
        let record = MeetingRecord(startedAt: date, endedAt: date.addingTimeInterval(65),
                                   languagePair: .englishToEnglish, lineCount: 2, status: .ended)

        XCTAssertEqual(record.displayDate, "Jul 7, 2026 at 18:27")
        XCTAssertEqual(record.metaText, "2 sections · 1m 5s")
        record.lineCount = 1
        XCTAssertEqual(record.metaText, "1 section · 1m 5s")
        record.endedAt = date.addingTimeInterval(5)
        XCTAssertEqual(record.durationText, "5s")
    }
}
