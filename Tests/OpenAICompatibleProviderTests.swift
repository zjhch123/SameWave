import XCTest
@testable import 同频

final class OpenAICompatibleProviderTests: XCTestCase {
    func testRequestBodyUsesStrictJSONSchema() throws {
        let data = try OpenAICompatibleProvider.makeRequestBody(
            model: "test-model",
            system: "system",
            user: "user",
            temperature: 0.3,
            schema: InsightResult.responseSchema
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])

        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        XCTAssertEqual(jsonSchema["name"] as? String, "insight_result")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(
            schema["required"] as? [String],
            ["topic", "suggestions", "answer", "todos", "decisions"]
        )
    }

    func testBuiltInProvidersUseDocumentedStructuredOutputModels() {
        XCTAssertEqual(LLMProviderConfig.builtIn.map(\.id), ["qwen", "kimi", "custom"])
        XCTAssertEqual(LLMProviderConfig.qwen.defaultModel, "qwen3.8-flash")
        XCTAssertEqual(LLMProviderConfig.kimi.defaultModel, "kimi-k3")
    }

    func testResponseRejectsTruncationAndRefusal() throws {
        let truncated = try XCTUnwrap(
            #"{"choices":[{"finish_reason":"length","message":{"content":"{}"}}]}"#
                .data(using: .utf8)
        )
        let refused = try XCTUnwrap(
            #"{"choices":[{"finish_reason":"stop","message":{"content":null,"refusal":"blocked"}}]}"#
                .data(using: .utf8)
        )

        XCTAssertThrowsError(try OpenAICompatibleProvider.parseContent(from: truncated)) {
            XCTAssertEqual($0 as? LLMError, .truncated)
        }
        XCTAssertThrowsError(try OpenAICompatibleProvider.parseContent(from: refused)) {
            XCTAssertEqual($0 as? LLMError, .refused("blocked"))
        }
    }
}
