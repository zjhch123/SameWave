import Foundation

/// Generates one concise meeting title in a request that is independent from transcript
/// refinement. The caller owns cancellation and persistence so title and refinement can
/// succeed or fail without coupling their outcomes.
@MainActor
final class MeetingTitleGenerator {
    private struct Response: Decodable {
        let title: String
    }

    private let settings: AISettings

    /// Fixed provider-independent budget shared with one-shot insights. A title uses the
    /// latest complete conversation lines and does not wait for refined text.
    static let contextCharacterLimit = 6_000
    static let titleCharacterLimit = 60

    init(settings: AISettings) {
        self.settings = settings
    }

    func generate(lines: [TranscriptLine]) async throws -> String {
        guard let provider = settings.makeProvider() else { throw LLMError.notConfigured }
        return try await Self.generate(lines: lines, provider: provider)
    }

    static func generate(lines: [TranscriptLine], provider: LLMProvider) async throws -> String {
        let transcript = input(lines: lines, limit: contextCharacterLimit)
        guard !transcript.isEmpty else { throw LLMError.emptyContent }

        let raw = try await provider.complete(
            system: systemPrompt(),
            user: transcript,
            schema: responseSchema
        )
        try Task.checkCancellation()
        guard let title = parse(raw) else { throw LLMError.schemaViolation }
        return title
    }

    static func input(lines: [TranscriptLine], limit: Int) -> String {
        InsightEngine.recentContext(
            from: InsightEngine.flatten(
                lines: lines,
                preferringRefinedSource: false
            ),
            limit: limit
        )
    }

    static func systemPrompt() -> String {
        """
        You are a meeting title editor. Generate a specific, recognizable English title from the conversation.
        Return a JSON object containing only the title field.
        Summarize the central topic, preferably using project, product, or task names from the conversation. Use 3–8 words and no more than \(titleCharacterLimit) characters. Avoid generic titles such as "Meeting Notes" or "Discussion". Do not add dates, quotation marks, a final period, explanations, or information absent from the conversation.
        """
    }

    static let responseSchema = LLMResponseSchema(
        name: "meeting_title",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("A specific, recognizable English meeting title")
                ])
            ]),
            "required": .array([.string("title")]),
            "additionalProperties": .bool(false)
        ])
    )

    static func parse(_ raw: String) -> String? {
        guard let response = JSONResponseParser.decode(Response.self, from: raw) else { return nil }
        let title = response.title
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmed
        guard !title.isEmpty else { return nil }
        return String(title.prefix(titleCharacterLimit))
    }
}
