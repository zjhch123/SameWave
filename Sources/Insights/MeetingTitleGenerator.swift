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

    /// A title-specific character budget. A title uses the
    /// latest complete conversation lines and does not wait for refined text.
    static let contextCharacterLimit = 6_000
    static let titleCharacterLimit = 60

    init(settings: AISettings) {
        self.settings = settings
    }

    func generateIfNeeded(for record: MeetingRecord) async throws -> String? {
        try await Self.generateIfNeeded(for: record, provider: settings.makeProvider())
    }

    static func generateIfNeeded(for record: MeetingRecord, provider: LLMProvider?) async throws -> String? {
        guard record.needsAITitle else { return nil }
        guard let provider else { throw LLMError.notConfigured }
        let title = try await generate(lines: record.lines, provider: provider)
        guard record.needsAITitle else { return nil }
        return title
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
        let transcript = lines.sorted { $0.orderIndex < $1.orderIndex }.compactMap { line -> String? in
            let text = line.sourceText.trimmed
            return text.isEmpty ? nil : "\(line.isMine ? "Me" : "Other party"): \(text)"
        }.joined(separator: "\n")
        return recentContext(from: transcript, limit: limit)
    }

    /// Keeps complete newest lines until the character budget is full. If a single
    /// line exceeds the budget, its newest suffix is retained rather than sending an
    /// oversized request.
    private static func recentContext(from transcript: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let trimmed = transcript.trimmed
        guard trimmed.count > limit else { return trimmed }

        var selected: [String] = []
        var count = 0
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            let value = String(line)
            let additional = value.count + (selected.isEmpty ? 0 : 1)
            if additional + count > limit {
                if selected.isEmpty { return String(value.suffix(limit)) }
                break
            }
            selected.append(value)
            count += additional
        }
        return selected.reversed().joined(separator: "\n")
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
