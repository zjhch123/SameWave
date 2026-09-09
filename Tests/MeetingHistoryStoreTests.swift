import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class MeetingHistoryStoreTests: XCTestCase {
    func testPersistentHistoryReopensWithoutTouchingSharedDefaultStore() throws {
        let support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: support) }
        let sharedStore = support.appending(path: "default.store")
        let unrelatedData = Data("Unrelated application's store".utf8)
        try unrelatedData.write(to: sharedStore)

        let configuration = try MeetingHistoryStore.persistentConfiguration(applicationSupportDirectory: support)
        XCTAssertEqual(configuration.url, support.appending(path: "SameWave/MeetingHistory.store"))
        let id: UUID
        do {
            let history = try MeetingHistoryStore(configuration: configuration)
            let record = try history.createDraft(languagePair: .englishToSimplifiedChinese)
            id = record.id
            record.userTitle = "Persistent meeting"
            var section = Section(id: 7, speaker: .remote)
            section.committedSource = ["Keep this transcript"]
            try history.finish(record, sections: [section], endedAt: .now)
        }

        XCTAssertEqual(try Data(contentsOf: sharedStore), unrelatedData)
        // A different application can replace its own store without changing our history.
        let replacement = Data("Other application's updated schema".utf8)
        try replacement.write(to: sharedStore)
        let reopened = try MeetingHistoryStore(configuration:
            MeetingHistoryStore.persistentConfiguration(applicationSupportDirectory: support))
        let record = try XCTUnwrap(reopened.context.fetch(FetchDescriptor<MeetingRecord>()).first)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.userTitle, "Persistent meeting")
        XCTAssertEqual(record.lines.map(\.sourceText), ["Keep this transcript"])
        XCTAssertEqual(record.meetingStatus, .ended)
        XCTAssertEqual(try Data(contentsOf: sharedStore), replacement)
    }

    func testPersistentStorageDirectoryFailureIsReported() throws {
        let support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: support) }
        try Data("Blocking file".utf8).write(to: support.appending(path: "SameWave"))
        XCTAssertThrowsError(try MeetingHistoryStore.persistentConfiguration(applicationSupportDirectory: support))
    }

    func testInterruptedCumulativeHypothesesPersistInTurnOrderWithoutDuplicates() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToSimplifiedChinese)
        let store = CaptionStore()
        store.updateSource("The release is ready", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("My reply", speaker: .mine, isFinal: false)
        try history.sync(record: record, sections: store.sections, endedAt: .now)
        store.updateSource("The release is ready for review", speaker: .remote, isFinal: false)
        try history.sync(record: record, sections: store.sections, endedAt: .now)
        store.updateSource("The release was ready for review.", speaker: .remote, isFinal: true)
        store.updateSource("My reply continues", speaker: .mine, isFinal: false, at: .now.advanced(by: .seconds(2)))
        store.endTurn(.remote)
        store.endTurn(.mine)
        try history.finish(record, sections: store.sections, endedAt: .now)
        let lines = record.lines.sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(lines.map(\.sectionId), [0, 1, 2, 3])
        XCTAssertEqual(lines.map(\.sourceText), ["The release was ready", "My reply", "for review.", "continues"])
        XCTAssertEqual(lines.map(\.isMine), [false, true, false, true])
        XCTAssertEqual(record.meetingStatus, .ended)
        let markdown = TranscriptExporter.markdown(record: record)
        XCTAssertTrue(markdown.contains("**1. [\(lines[0].timeText)] Other party:** The release was ready"))
        XCTAssertTrue(markdown.contains("**2. [\(lines[1].timeText)] Me:** My reply"))
        XCTAssertTrue(markdown.contains("**3. [\(lines[2].timeText)] Other party:** for review."))
        XCTAssertTrue(markdown.contains("**4. [\(lines[3].timeText)] Me:** continues"))
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
