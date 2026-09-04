import SwiftData
import XCTest
@testable import 同频

@MainActor
final class MeetingHistoryStoreTests: XCTestCase {
    func testSyncUpsertsBySectionIDAndDeletesPrunedLines() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.beginRecord(
            startedAt: .now,
            languagePair: .englishToSimplifiedChinese
        )

        var first = Section(id: 10, speaker: .remote)
        first.committedSource = ["Hello"]
        var second = Section(id: 11, speaker: .mine)
        second.committedSource = ["Hi"]
        try history.sync(record: record, sections: [first, second], endedAt: .now)

        first.targetText = "你好"
        try history.sync(record: record, sections: [first], endedAt: .now)

        XCTAssertEqual(record.lineCount, 1)
        XCTAssertEqual(record.lines.count, 1)
        XCTAssertEqual(record.lines[0].sectionId, 10)
        XCTAssertEqual(record.lines[0].targetText, "你好")
    }

    func testFinishDeletesEmptyMeeting() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.beginRecord(
            startedAt: .now,
            languagePair: .simplifiedChineseToSimplifiedChinese
        )

        try history.finish(record, sections: [], endedAt: .now)

        let records = try history.context.fetch(FetchDescriptor<MeetingRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    func testFinishPersistsTranscriptAndEndedStatusTogether() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.beginRecord(
            startedAt: .now,
            languagePair: .simplifiedChineseToEnglish
        )
        var section = Section(id: 7, speaker: .remote)
        section.committedSource = ["Finished"]

        try history.finish(record, sections: [section], endedAt: .now)

        XCTAssertEqual(record.meetingStatus, .ended)
        XCTAssertEqual(record.languagePair, .simplifiedChineseToEnglish)
        XCTAssertEqual(record.lineCount, 1)
        XCTAssertEqual(record.lines.first?.sectionId, 7)
    }

    func testAITitlePersistsAndReplacesDateWhileDateRemainsInMetadata() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.beginRecord(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            languagePair: .englishToSimplifiedChinese
        )

        XCTAssertEqual(record.displayTitle, record.displayDate)
        XCTAssertEqual(record.displayMetaText, record.metaText)
        XCTAssertFalse(record.hasAITitle)

        record.aiTitle = "项目交付时间与风险讨论"
        try history.save()

        let fetched = try XCTUnwrap(
            history.context.fetch(FetchDescriptor<MeetingRecord>()).first
        )
        XCTAssertEqual(fetched.aiTitle, "项目交付时间与风险讨论")
        XCTAssertTrue(fetched.hasAITitle)
        XCTAssertEqual(fetched.displayTitle, "项目交付时间与风险讨论")
        XCTAssertTrue(fetched.displayMetaText.hasPrefix(fetched.displayDate))
    }

    func testBlankAITitleFallsBackToDate() {
        let record = MeetingRecord(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_010),
            languagePair: .englishToSimplifiedChinese,
            lineCount: 1,
            status: .ended,
            aiTitle: "  \n "
        )

        XCTAssertEqual(record.displayTitle, record.displayDate)
        XCTAssertFalse(record.hasAITitle)
    }
}
