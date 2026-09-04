import Foundation

/// Generates one concise meeting title in a request that is independent from transcript
/// refinement. The caller owns cancellation and persistence so title and refinement can
/// succeed or fail without coupling their outcomes.
@MainActor
final class MeetingTitleGenerator {
    private struct Response: Decodable {
        let title: String
    }

    private let settings: InsightSettings

    /// Fixed provider-independent budget shared with one-shot insights. A title uses the
    /// latest complete conversation lines and does not wait for refined text.
    static let contextCharacterLimit = 6_000
    static let titleCharacterLimit = 30

    init(settings: InsightSettings) {
        self.settings = settings
    }

    func generate(lines: [TranscriptLine]) async throws -> String {
        guard let provider = settings.makeProvider() else { throw LLMError.notConfigured }
        return try await Self.generate(lines: lines, provider: provider)
    }

    static func generate(lines: [TranscriptLine], provider: InsightProvider) async throws -> String {
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
            from: InsightEngine.flatten(lines: lines),
            limit: limit
        )
    }

    static func systemPrompt() -> String {
        """
        你是会议标题编辑。请根据会议对话生成一个具体、易识别的简体中文标题。
        输出必须是一个只包含 title 字段的 JSON 对象。
        标题应概括会议的核心议题，优先使用对话中的项目、产品或事项名称，控制在 6 到 20 个汉字；不要使用“会议记录”“沟通讨论”等空泛标题，不要添加日期、引号、句号或解释，不得虚构对话中没有的信息。
        """
    }

    static let responseSchema = LLMResponseSchema(
        name: "meeting_title",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("具体、易识别的简体中文会议标题")
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
