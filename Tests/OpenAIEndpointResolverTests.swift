import XCTest
@testable import SameWave

final class OpenAIEndpointResolverTests: XCTestCase {
    func testBareRemoteHostUsesOpenAIStandardV1Path() {
        XCTAssertEqual(
            OpenAIEndpointResolver.chatCompletionsURL(from: "api.example.com")?.absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
    }

    func testBareLocalHostUsesHTTP() {
        XCTAssertEqual(
            OpenAIEndpointResolver.chatCompletionsURL(
                from: "127.0.0.1:23333"
            )?.absoluteString,
            "http://127.0.0.1:23333/v1/chat/completions"
        )
    }

    func testVersionedBaseAppendsOnlyChatCompletions() {
        XCTAssertEqual(
            OpenAIEndpointResolver.chatCompletionsURL(
                from: "https://gateway.example.com/compatible-mode/v1/"
            )?.absoluteString,
            "https://gateway.example.com/compatible-mode/v1/chat/completions"
        )
    }

    func testCompleteEndpointIsKeptAndFragmentIsRemoved() {
        XCTAssertEqual(
            OpenAIEndpointResolver.chatCompletionsURL(
                from: "https://gateway.example.com/v4/chat/completions/#docs"
            )?.absoluteString,
            "https://gateway.example.com/v4/chat/completions"
        )
    }

    func testModelsURLIsSiblingOfChatRouteAndPreservesQuery() {
        XCTAssertEqual(
            OpenAIEndpointResolver.modelsURL(
                from: "https://gateway.example.com/v1/chat/completions?api-version=1"
            )?.absoluteString,
            "https://gateway.example.com/v1/models?api-version=1"
        )
    }

    func testInvalidAddressIsRejected() {
        XCTAssertNil(OpenAIEndpointResolver.chatCompletionsURL(from: "https:///missing-host"))
    }

    func testUnsupportedSchemesAreRejectedInsteadOfBecomingHostnames() {
        for address in ["ftp://example.com", "file:///tmp/model", "ws://localhost:8080"] {
            XCTAssertNil(OpenAIEndpointResolver.chatCompletionsURL(from: address))
            XCTAssertNil(OpenAIEndpointResolver.modelsURL(from: address))
        }
    }

    func testModelDecodesGatewayOwnerWithoutChangingID() throws {
        let data = Data(#"{"id":"provider:model","owned_by":"Provider"}"#.utf8)

        let model = try JSONDecoder().decode(LLMModel.self, from: data)

        XCTAssertEqual(model.id, "provider:model")
        XCTAssertEqual(model.ownedBy, "Provider")
    }
}
