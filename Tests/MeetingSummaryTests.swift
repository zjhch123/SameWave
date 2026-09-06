import XCTest
@testable import SameWave

@MainActor
final class MeetingSummaryTests: XCTestCase {
    func testLiveOverviewAndFullSummaryUseTheSameNamedParts() throws {
        let result = InsightResult(conclusion: "Conditional launch", points: [], summary: Phase2Fixture.summary)
        let raw = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        for kind in [InsightKind.automatic, .manual, .summary] {
            let parsed = try InsightResult.parse(raw, kind: kind)
            XCTAssertEqual(parsed.summary, Phase2Fixture.summary)
            XCTAssertTrue(parsed.points.isEmpty)
        }
        XCTAssertTrue(InsightRequest.systemPrompt.contains("live cumulative overviews"))
        XCTAssertTrue(InsightRequest.systemPrompt.contains("never agreed actions"))
    }

    func testFocusedInsightsUseExplicitNullButFullSummaryRequiresParts() throws {
        let raw = #"{"conclusion":"Focused answer","points":["A useful point"],"summary":null}"#
        XCTAssertNil(try InsightResult.parse(raw).summary)
        XCTAssertThrowsError(try InsightResult.parse(raw, kind: .summary))
        XCTAssertThrowsError(try InsightResult.parse(
            #"{"conclusion":"Answer","points":[]}"#))
    }

    func testNamedPartsRejectMissingFieldsBlankItemsAndExcessContent() throws {
        let good = InsightResult(conclusion: "Overview", points: [], summary: Phase2Fixture.summary)
        let data = try JSONEncoder().encode(good)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summary = try XCTUnwrap(object["summary"] as? [String: Any])
        for replacement: Any in [NSNull(), [""], [String(repeating: "x", count: 501)], Array(repeating: "Decision", count: 9)] {
            var changedSummary = summary
            changedSummary["decisions"] = replacement
            var changed = object
            changed["summary"] = changedSummary
            let raw = String(decoding: try JSONSerialization.data(withJSONObject: changed), as: UTF8.self)
            XCTAssertThrowsError(try InsightResult.parse(raw, kind: .summary))
        }
        var missing = summary
        missing.removeValue(forKey: "actionItems")
        var changed = object
        changed["summary"] = missing
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: changed), as: UTF8.self)
        XCTAssertThrowsError(try InsightResult.parse(raw, kind: .summary))
        var duplicated = object
        duplicated["points"] = ["Duplicate summary content"]
        let duplicatedRaw = String(decoding: try JSONSerialization.data(withJSONObject: duplicated), as: UTF8.self)
        XCTAssertThrowsError(try InsightResult.parse(duplicatedRaw))
    }

    func testAbsentFactsRemainEmptyAndSavedPartsRemainImmutable() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let configuration = try XCTUnwrap(record.definitions.first).configuration
        let input = Phase2Fixture.input(record: record, configuration: configuration, kind: .manual)
        let parts = MeetingSummary(topics: ["Security review"], decisions: [], actionItems: [], openQuestions: [], suggestions: [])
        let value = InsightSnapshotValue(id: UUID(), input: input, completedAt: .now,
            result: InsightResult(conclusion: "Review in progress", points: [], summary: parts))
        try history.appendInsight(value)
        record.definitions[0].prompt = "Changed instructions"
        try history.save()
        let restored = try XCTUnwrap(record.insightSnapshots.first).decoded()
        XCTAssertEqual(restored, value)
        XCTAssertTrue(try XCTUnwrap(restored.result.summary).decisions.isEmpty)
        let markdown = TranscriptExporter.markdown(record: record)
        XCTAssertTrue(markdown.contains("No decisions recorded."))
        XCTAssertTrue(markdown.contains("No action items assigned."))
    }
}
