import SwiftData
import XCTest
@testable import 同频

@MainActor
final class MeetingHistoryStoreTests: XCTestCase {
    func testSyncUpsertsBySectionIDAndDeletesPrunedLines() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.beginRecord(startedAt: .now, language: .english)

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
        let record = try history.beginRecord(startedAt: .now, language: .chinese)

        try history.finish(record, sections: [], endedAt: .now)

        let records = try history.context.fetch(FetchDescriptor<MeetingRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    func testFinishPersistsTranscriptAndEndedStatusTogether() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let history = try MeetingHistoryStore(configuration: configuration)
        let record = try history.beginRecord(startedAt: .now, language: .english)
        var section = Section(id: 7, speaker: .remote)
        section.committedSource = ["Finished"]

        try history.finish(record, sections: [section], endedAt: .now)

        XCTAssertEqual(record.meetingStatus, .ended)
        XCTAssertEqual(record.lineCount, 1)
        XCTAssertEqual(record.lines.first?.sectionId, 7)
    }
}
