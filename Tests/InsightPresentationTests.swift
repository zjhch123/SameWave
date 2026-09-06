import XCTest
@testable import SameWave

@MainActor
final class InsightPresentationTests: XCTestCase {
    func testPaletteKeepsIdentityThroughRemovalReorderingAndNewItems() {
        let ids = (0..<6).map { _ in UUID() }
        var palette = InsightCardPalette()
        palette.include(Array(ids.prefix(4)))
        XCTAssertEqual(ids.prefix(4).map { palette.slots[$0] }, [0, 1, 2, 3])
        palette.include([ids[3], ids[1], ids[4], ids[5]])
        XCTAssertEqual(ids.map { palette.slots[$0] }, [0, 1, 2, 3, 0, 1])
        palette.include(ids.reversed())
        XCTAssertEqual(ids.map { palette.slots[$0] }, [0, 1, 2, 3, 0, 1])
    }

    func testUserDefinitionsStayAboveRenamedOverviewWithoutChangingColors() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let overview = try XCTUnwrap(record.definitions.first)
        var palette = InsightCardPalette()
        palette.include([overview.id])
        let older = InsightDefinition(title: "Risks", prompt: "Find risks")
        older.createdAt = overview.createdAt.addingTimeInterval(1)
        let newer = InsightDefinition(title: "Meeting Overview", prompt: "My own focused question")
        newer.createdAt = overview.createdAt.addingTimeInterval(2)
        for item in [older, newer] { item.record = record; history.context.insert(item) }
        try history.save()
        palette.include(record.orderedDefinitions.map(\.id))
        overview.title = "Renamed default"
        XCTAssertEqual(record.insightReadingOrder.map(\.id), [newer.id, older.id, overview.id])
        XCTAssertEqual(palette.slots[overview.id], 0)
        XCTAssertEqual(palette.slots[newer.id], 2)
        history.context.delete(overview)
        try history.save()
        XCTAssertEqual(record.insightReadingOrder.map(\.id), [newer.id, older.id])
    }

    func testCardsKeepIndependentHistoryAndExpansionThroughNewResults() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let configuration = try XCTUnwrap(record.definitions.first).configuration
        let old = try InsightSnapshot(Phase2Fixture.snapshot(record: record, configuration: configuration,
            now: Date(timeIntervalSince1970: 100)))
        let latest = try InsightSnapshot(Phase2Fixture.snapshot(record: record, configuration: configuration,
            now: Date(timeIntervalSince1970: 200)))
        var first = InsightCardReadingState()
        first.timeline.snapshotID = old.id
        first.conclusionExpanded = false
        var second = InsightCardReadingState()
        second.timeline.snapshotID = latest.id
        XCTAssertEqual(first.timeline.selected(from: [latest, old])?.id, old.id)
        XCTAssertFalse(first.conclusionExpanded)
        XCTAssertTrue(second.conclusionExpanded)
        second.timeline.snapshotID = nil
        XCTAssertEqual(second.timeline.selected(from: [old, latest])?.id, latest.id)
        XCTAssertEqual(first.timeline.selected(from: [old, latest])?.id, old.id)
    }

    func testArchiveKeepsRemovedIdentityVersionsAndExcludesSummaryAndActiveDefinitions() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let removed = try XCTUnwrap(record.definitions.first)
        let original = Phase2Fixture.snapshot(record: record, configuration: removed.configuration,
                                             kind: .manual, now: Date(timeIntervalSince1970: 100))
        try history.appendInsight(original)
        removed.title = "Renamed overview"
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: removed.configuration,
            kind: .manual, now: Date(timeIntervalSince1970: 200)))
        try history.appendInsight(Phase2Fixture.snapshot(record: record))
        let active = InsightDefinition(title: "Renamed overview", prompt: "An independent insight with the same title")
        active.record = record
        history.context.insert(active)
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: active.configuration, kind: .manual))
        XCTAssertTrue(record.archivedInsightConfigurations.isEmpty)
        let removedID = removed.id
        history.context.delete(removed)
        try history.save()
        XCTAssertEqual(record.archivedInsightConfigurations.map(\.id), [removedID])
        XCTAssertEqual(record.archivedInsightConfigurations.first?.title, "Renamed overview")
        XCTAssertEqual(record.insightSnapshots.filter { $0.definitionID == removedID }.count, 2)
        XCTAssertEqual(try record.insightSnapshots.first { $0.id == original.id }?.decoded(), original)
    }
}
