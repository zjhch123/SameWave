import Foundation
import Observation

/// Generates rolling and one-shot structured insights. Refining transcript text is
/// intentionally handled by `TranscriptRefiner`, which has a different batching and
/// failure model.
@MainActor
@Observable
final class InsightEngine {
    enum State: Equatable {
        case idle
        case generating
        case done
        case error(LLMError)
    }

    private(set) var current: InsightResult = .empty
    private(set) var state: State = .idle

    private let settings: InsightSettings
    private let sentencesPerRefresh = 6
    private var sentencesSinceGeneration = 0
    private var lastSpeaker: Speaker?
    private var isGenerating = false
    private var changedWhileGenerating = false
    private var latestTranscript = ""
    private var liveTask: Task<Void, Never>?
    private var liveToken = UUID()

    /// Fixed to fit the smallest built-in 8K context after prompt and output space.
    static let contextCharacterLimit = 6_000

    init(settings: InsightSettings) {
        self.settings = settings
    }

    var isConfigured: Bool { settings.isConfigured }

    func reset() {
        liveTask?.cancel()
        liveTask = nil
        liveToken = UUID()
        current = .empty
        state = .idle
        sentencesSinceGeneration = 0
        lastSpeaker = nil
        isGenerating = false
        changedWhileGenerating = false
        latestTranscript = ""
    }

    func noteNewFinalContent(sections: [Section], speaker: Speaker?) {
        guard settings.isConfigured else { return }
        latestTranscript = Self.recentContext(
            from: Self.flatten(sections: sections),
            limit: Self.contextCharacterLimit
        )
        guard !latestTranscript.isEmpty else { return }

        var shouldGenerate = false
        if let speaker, let lastSpeaker, speaker != lastSpeaker {
            shouldGenerate = true
        }
        if let speaker { lastSpeaker = speaker }
        sentencesSinceGeneration += 1
        if sentencesSinceGeneration >= sentencesPerRefresh { shouldGenerate = true }
        if shouldGenerate { triggerLiveGeneration() }
    }

    func generateOnce(transcript: String) async throws -> InsightResult {
        guard let provider = settings.makeProvider() else { throw LLMError.notConfigured }
        let input = Self.recentContext(from: transcript, limit: Self.contextCharacterLimit)
        guard !input.isEmpty else { return .empty }
        let raw = try await provider.complete(system: Self.systemPrompt(), user: input)
        guard let result = Self.parse(raw) else { throw LLMError.badResponse }
        return result
    }

    private func triggerLiveGeneration() {
        sentencesSinceGeneration = 0
        if isGenerating {
            changedWhileGenerating = true
            return
        }
        guard let provider = settings.makeProvider() else { return }

        isGenerating = true
        changedWhileGenerating = false
        state = .generating
        let transcript = latestTranscript
        let token = liveToken

        liveTask = Task { @MainActor [weak self] in
            let outcome = await Self.perform(
                provider: provider,
                transcript: transcript
            )
            guard let self, self.liveToken == token else { return }
            self.isGenerating = false
            switch outcome {
            case .success(let result):
                self.current = result
                self.state = .done
            case .failure(let error):
                self.state = .error(error)
            }
            if self.changedWhileGenerating, self.settings.isConfigured {
                self.changedWhileGenerating = false
                self.triggerLiveGeneration()
            }
        }
    }

    private static func perform(provider: InsightProvider,
                                transcript: String) async -> Result<InsightResult, LLMError> {
        do {
            let raw = try await provider.complete(
                system: systemPrompt(),
                user: transcript
            )
            guard let result = parse(raw) else { return .failure(.badResponse) }
            return .success(result)
        } catch let error as LLMError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    static func flatten(sections: [Section]) -> String {
        sections.compactMap { section in
            let text = section.sourceText.trimmed
            guard !text.isEmpty else { return nil }
            return "\(section.speaker == .mine ? "我" : "对方")：\(text)"
        }
        .joined(separator: "\n")
    }

    static func flatten(lines: [TranscriptLine]) -> String {
        lines.sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { line in
                let text = line.sourceText.trimmed
                guard !text.isEmpty else { return nil }
                return "\(line.isMine ? "我" : "对方")：\(text)"
            }
            .joined(separator: "\n")
    }

    /// Keeps complete newest lines until the character budget is full. If a single
    /// line exceeds the budget, its newest suffix is retained rather than sending an
    /// oversized request.
    static func recentContext(from transcript: String, limit: Int) -> String {
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
        你是一个实时会议助手。下面是会议最近的对话（“我”是使用者，“对方”是其他参会者）。
        请只返回 JSON 对象，不要解释或 markdown：
        {
          "topic": "用一两句话概括当前话题",
          "suggestions": ["给我的下一步建议或追问"],
          "answer": "对方刚提问时的参考回答，否则为空字符串",
          "todos": [{"who": "负责人", "what": "待办"}],
          "decisions": ["已达成的决定"]
        }
        所有内容使用简体中文。suggestions 限 1-3 条。只依据对话中出现的信息，没有的字段返回空值，不要编造。
        """
    }

    static func parse(_ raw: String) -> InsightResult? {
        JSONResponseParser.decode(InsightResult.self, from: raw)
    }
}

enum JSONResponseParser {
    static func decode<Value: Decodable>(_ type: Value.Type, from raw: String) -> Value? {
        let cleaned = stripFence(raw)
        if let data = cleaned.data(using: .utf8),
           let value = try? JSONDecoder().decode(type, from: data) {
            return value
        }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              start < end,
              let data = String(cleaned[start...end]).data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func stripFence(_ value: String) -> String {
        var result = value.trimmed
        if result.hasPrefix("```"), let newline = result.firstIndex(of: "\n") {
            result = String(result[result.index(after: newline)...])
            if let fence = result.range(of: "```", options: .backwards) {
                result = String(result[..<fence.lowerBound])
            }
        }
        return result.trimmed
    }
}
