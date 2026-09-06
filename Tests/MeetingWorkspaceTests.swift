import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class MeetingWorkspaceTests: XCTestCase {
    func testReadingOlderSnapshotDoesNotFollowNewArrivalUntilLatestIsSelected() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let first = try InsightSnapshot(Phase2Fixture.snapshot(record: record, now: Date(timeIntervalSince1970: 100)))
        let second = try InsightSnapshot(Phase2Fixture.snapshot(record: record, now: Date(timeIntervalSince1970: 200)))
        var selection = InsightTimelineSelection(snapshotID: first.id)
        XCTAssertEqual(selection.selected(from: [first])?.id, first.id)
        XCTAssertEqual(selection.selected(from: [second, first])?.id, first.id)
        selection.snapshotID = nil
        XCTAssertEqual(selection.selected(from: [first, second])?.id, second.id)
    }

    func testPreparedDraftAndSnapshotsSurviveDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("meetings.store")
        let id: UUID
        let value: InsightSnapshotValue
        do {
            let history = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
            let draft = try history.createDraft(languagePair: .englishToSimplifiedChinese,
                                                 now: Date(timeIntervalSince1970: 100))
            draft.userTitle = "Release Review"
            draft.definitions[0].prompt = "Identify release risks"
            draft.definitions[0].automaticallyUpdates = true
            try history.attach([.init(fileName: "context.md", content: "XPay launch plan")], to: draft)
            try history.replaceVocabulary(["XPay"], in: draft)
            value = Phase2Fixture.snapshot(record: draft, configuration: draft.definitions[0].configuration, kind: .manual)
            try history.appendInsight(value)
            id = draft.id
        }
        let reopened = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
        let saved = try XCTUnwrap(reopened.record(id: id))
        XCTAssertEqual(saved.meetingStatus, .draft)
        XCTAssertEqual(saved.userTitle, "Release Review")
        XCTAssertEqual(saved.documents.first?.content, "XPay launch plan")
        XCTAssertEqual(saved.confirmedVocabulary, ["XPay"])
        XCTAssertEqual(saved.definitions[0].prompt, "Identify release risks")
        XCTAssertTrue(saved.definitions[0].automaticallyUpdates)
        XCTAssertEqual(try saved.insightSnapshots[0].decoded(), value)
    }

    func testDraftSurvivesStartupFailureAndEmptyFinishWithSeparateCreationTime() throws {
        let history = try Phase2Fixture.history()
        let created = Date(timeIntervalSince1970: 100)
        let started = created.addingTimeInterval(3_600)
        let record = try history.createDraft(languagePair: .englishToEnglish, now: created)
        record.userTitle = "Prepared title"
        try history.attach([.init(fileName: "notes.md", content: "Preparation")], to: record)
        try history.beginCapture(record, languagePair: .englishToEnglish, now: started)
        try history.setStatus(record, .draft)
        let defaults = Phase2Fixture.defaults(self)
        defaults.set(record.id.uuidString, forKey: "selectedMeetingID")
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        coordinator.restoreSelection()
        XCTAssertEqual(coordinator.workspaceRecord?.meetingStatus, .draft)
        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertEqual(record.createdAt, created)
        XCTAssertEqual(record.startedAt, started)
        try history.finish(record, sections: [], endedAt: started)
        XCTAssertNotNil(try history.record(id: record.id))
        XCTAssertEqual(record.documents.count, 1)
        XCTAssertEqual(record.userTitle, "Prepared title")
    }

    func testMeetingVocabularyIsolationPrecedenceAndTermRetentionAfterAttachmentRemoval() throws {
        let history = try Phase2Fixture.history()
        let a = try history.createDraft(languagePair: .englishToEnglish)
        let b = try history.createDraft(languagePair: .englishToEnglish)
        let defaults = Phase2Fixture.defaults(self)
        let global = SpeechVocabularySettings(defaults: defaults)
        global.save(["xpay", "Personal"])
        try history.attach([.init(fileName: "a.md", content: "XPay")], to: a)
        try history.replaceVocabulary(["XPay"], in: a)
        XCTAssertEqual(a.effectiveVocabulary(global: global.phrases), ["XPay", "Personal"])
        XCTAssertEqual(b.effectiveVocabulary(global: global.phrases), ["xpay", "Personal"])
        XCTAssertEqual(global.phrases, ["xpay", "Personal"])
        try history.removeAttachment(a.documents[0])
        XCTAssertTrue(a.documents.isEmpty)
        XCTAssertEqual(try history.context.fetchCount(FetchDescriptor<MeetingDocument>()), 0)
        XCTAssertEqual(a.confirmedVocabulary, ["XPay"])
    }

    func testDuplicateAttachmentsAreSkippedAndOversizeImportIsAtomic() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let source = VocabularySourceDocument(fileName: "notes.md", content: "Original")
        try history.attach([source], to: record)
        try history.attach([source], to: record)
        XCTAssertEqual(record.documents.count, 1)
        XCTAssertThrowsError(try history.attach([
            .init(fileName: "small.md", content: "Small"),
            .init(fileName: "large.md", content: String(repeating: "a", count: 3_000_001))
        ], to: record))
        XCTAssertEqual(record.documents.count, 1)
        XCTAssertEqual(record.documents[0].content, "Original")
    }

    func testRepeatedNewAttachmentCountsOnceNearMeetingLimit() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let content = String(repeating: "a", count: VocabularyDocumentLoader.maximumFileBytes)
        try history.attach((1...9).map { .init(fileName: "existing-\($0).md", content: content) }, to: record)
        let added = VocabularySourceDocument(fileName: "new.md", content: content)
        try history.attach([added, added], to: record)
        XCTAssertEqual(record.documents.count, 10)
        XCTAssertEqual(record.documents.filter { $0.fileName == "new.md" }.count, 1)
        XCTAssertThrowsError(try history.attach([.init(fileName: "overflow.md", content: "x")], to: record))
        XCTAssertEqual(record.documents.count, 10)
    }

    func testDeletingDefinitionRetainsHistoryAndMeetingDeletionCascades() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.attach([.init(fileName: "notes.md", content: "XPay")], to: record)
        try history.replaceVocabulary(["XPay"], in: record)
        let definition = record.definitions[0]
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: definition.configuration, kind: .manual))
        history.context.delete(definition)
        try history.save()
        XCTAssertEqual(record.insightSnapshots.count, 1)
        try history.delete(record)
        XCTAssertTrue(try history.context.fetch(FetchDescriptor<MeetingDocument>()).isEmpty)
        XCTAssertTrue(try history.context.fetch(FetchDescriptor<MeetingVocabularyTerm>()).isEmpty)
        XCTAssertTrue(try history.context.fetch(FetchDescriptor<InsightDefinition>()).isEmpty)
        XCTAssertTrue(try history.context.fetch(FetchDescriptor<InsightSnapshot>()).isEmpty)
    }

    func testUserTitleAlwaysTakesPrecedenceOverAITitle() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.userTitle = "My chosen title"
        record.aiTitle = "Generated title"
        try history.save()
        XCTAssertEqual(record.displayTitle, "My chosen title")
    }
}
