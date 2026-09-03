import XCTest
@testable import 同频

@MainActor
final class InsightEngineTests: XCTestCase {
    func testRecentContextKeepsNewestCompleteLines() {
        let transcript = ["older line", "middle line", "newest line"].joined(separator: "\n")

        let context = InsightEngine.recentContext(from: transcript, limit: 23)

        XCTAssertEqual(context, "middle line\nnewest line")
    }

    func testRecentContextTruncatesSingleOversizedLineFromFront() {
        XCTAssertEqual(
            InsightEngine.recentContext(from: "0123456789", limit: 4),
            "6789"
        )
    }

    func testParsesFencedJSONResponse() {
        let raw = """
        ```json
        {"topic":"Roadmap","suggestions":[],"answer":"","todos":[],"decisions":[]}
        ```
        """

        XCTAssertEqual(InsightEngine.parse(raw)?.topic, "Roadmap")
    }
}
