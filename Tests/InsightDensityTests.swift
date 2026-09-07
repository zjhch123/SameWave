import XCTest
@testable import SameWave

final class InsightDensityTests: XCTestCase {
    func testFocusedResponseKeepsIndependentPointsWithoutACountQuota() throws {
        let boundary = InsightResult(conclusion: String(repeating: "a", count: 300),
            points: (0..<20).map { String(format: "%02d", $0) + String(repeating: "b", count: 238) })
        func raw(_ result: InsightResult) throws -> String {
            String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        }
        XCTAssertEqual(try InsightResult.parse(raw(boundary)), boundary)
        let absent = InsightResult(conclusion: "No WFH policy change was discussed.", points: [])
        XCTAssertEqual(try InsightResult.parse(raw(absent)), absent)
        for result in [
            InsightResult(conclusion: String(repeating: "a", count: 301), points: []),
            InsightResult(conclusion: "Conclusion", points: [String(repeating: "a", count: 241)])
        ] {
            XCTAssertThrowsError(try InsightResult.parse(raw(result))) {
                XCTAssertEqual($0 as? LLMError, .schemaViolation)
            }
        }
    }

    func testSchemaHasNoPointCountLimitAndRetainsTextValidation() throws {
        let data = try JSONEncoder().encode(InsightResult.responseSchema)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let schema = try XCTUnwrap(object["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let conclusion = try XCTUnwrap(properties["conclusion"] as? [String: Any])
        let points = try XCTUnwrap(properties["points"] as? [String: Any])
        let items = try XCTUnwrap(points["items"] as? [String: Any])
        XCTAssertEqual(conclusion["maxLength"] as? Int, 300)
        XCTAssertNil(points["maxItems"])
        XCTAssertNil(points["minItems"])
        XCTAssertEqual(items["maxLength"] as? Int, 240)
    }
}
