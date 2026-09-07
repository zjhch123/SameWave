import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class MeetingHistoryStoreTests: XCTestCase {
    func testOverlappingFinalsAndUnfinishedTailsPersistWithoutDuplicates() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToSimplifiedChinese)
        let store = CaptionStore()
        store.updateInterim("First hypothesis", speaker: .remote)
        store.updateInterim("Reply hypothesis", speaker: .mine)
        try history.sync(record: record, sections: store.sections, endedAt: .now)
        store.appendCommitted("Corrected first sentence.", speaker: .remote)
        store.appendCommitted("Corrected reply.", speaker: .mine)
        store.updateInterim("Unfinished tail", speaker: .mine)
        store.endTurn(.remote)
        store.endTurn(.mine)
        try history.finish(record, sections: store.sections, endedAt: .now)
        let lines = record.lines.sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(lines.map(\.sectionId), [0, 1])
        XCTAssertEqual(lines.map(\.sourceText), ["Corrected first sentence.", "Corrected reply. Unfinished tail"])
        XCTAssertEqual(record.meetingStatus, .ended)
    }

    func testSyncUpsertsBySectionIDAndDeletesPrunedLines() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.createDraft(
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

    func testFinishRetainsEmptyMeeting() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.createDraft(
            languagePair: .simplifiedChineseToSimplifiedChinese
        )

        try history.finish(record, sections: [], endedAt: .now)

        let records = try history.context.fetch(FetchDescriptor<MeetingRecord>())
        XCTAssertEqual(records.map(\.id), [record.id])
        XCTAssertEqual(records.first?.meetingStatus, .ended)
    }

    func testFinishPersistsTranscriptAndEndedStatusTogether() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.createDraft(
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
        let record = try history.createDraft(languagePair: .englishToSimplifiedChinese, now: Date(timeIntervalSince1970: 1_700_000_000))

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
