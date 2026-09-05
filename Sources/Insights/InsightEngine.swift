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

    private let settings: AISettings
    private let vocabularySettings: SpeechVocabularySettings
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

    init(settings: AISettings, vocabularySettings: SpeechVocabularySettings) {
        self.settings = settings
        self.vocabularySettings = vocabularySettings
    }

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
        let relevantVocabulary = Self.relevantVocabulary(
            from: input,
            configuredVocabulary: vocabularySettings.phrases
        )
        let raw = try await provider.complete(
            system: Self.systemPrompt(relevantVocabulary: relevantVocabulary),
            user: input,
            schema: InsightResult.responseSchema
        )
        guard let result = Self.parse(raw) else { throw LLMError.schemaViolation }
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
        let relevantVocabulary = Self.relevantVocabulary(
            from: transcript,
            configuredVocabulary: vocabularySettings.phrases
        )
        let token = liveToken

        liveTask = Task { @MainActor [weak self] in
            let outcome = await Self.perform(
                provider: provider,
                transcript: transcript,
                relevantVocabulary: relevantVocabulary
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

    private static func perform(
        provider: LLMProvider,
        transcript: String,
        relevantVocabulary: [String]
    ) async -> Result<InsightResult, LLMError> {
        do {
            let raw = try await provider.complete(
                system: systemPrompt(relevantVocabulary: relevantVocabulary),
                user: transcript,
                schema: InsightResult.responseSchema
            )
            guard let result = parse(raw) else { return .failure(.schemaViolation) }
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
            return "\(section.speaker == .mine ? "Me" : "Other party"): \(text)"
        }
        .joined(separator: "\n")
    }

    static func flatten(
        lines: [TranscriptLine],
        preferringRefinedSource: Bool
    ) -> String {
        lines.sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { line in
                let refinedSource = line.refinedSource?.trimmed
                let text = if preferringRefinedSource,
                              let refinedSource,
                              !refinedSource.isEmpty {
                    refinedSource
                } else {
                    line.sourceText.trimmed
                }
                guard !text.isEmpty else { return nil }
                return "\(line.isMine ? "Me" : "Other party"): \(text)"
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

    /// Returns configured terms that occur in the request context. Alphanumeric
    /// terms must match at word boundaries so a short entry such as "PR" does not
    /// match inside "project". Original configuration order and spelling are kept.
    static func relevantVocabulary(
        from transcript: String,
        configuredVocabulary: [String]
    ) -> [String] {
        guard !transcript.isEmpty else { return [] }
        let locale = Locale(identifier: "en_US_POSIX")

        return configuredVocabulary.filter { phrase in
            guard !phrase.isEmpty else { return false }
            let needsLeadingBoundary = phrase.first.map(Self.isLetterOrNumber) ?? false
            let needsTrailingBoundary = phrase.last.map(Self.isLetterOrNumber) ?? false
            var searchStart = transcript.startIndex

            while searchStart < transcript.endIndex,
                  let range = transcript.range(
                    of: phrase,
                    options: [.caseInsensitive, .literal],
                    range: searchStart..<transcript.endIndex,
                    locale: locale
                  ) {
                let leadingBoundaryMatches = !needsLeadingBoundary
                    || range.lowerBound == transcript.startIndex
                    || !Self.isLetterOrNumber(
                        transcript[transcript.index(before: range.lowerBound)]
                    )
                let trailingBoundaryMatches = !needsTrailingBoundary
                    || range.upperBound == transcript.endIndex
                    || !Self.isLetterOrNumber(transcript[range.upperBound])

                if leadingBoundaryMatches, trailingBoundaryMatches { return true }
                searchStart = transcript.index(after: range.lowerBound)
            }
            return false
        }
    }

    private static func isLetterOrNumber(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    static func systemPrompt(relevantVocabulary: [String]) -> String {
        let base = """
        You are a live meeting assistant. The input is the latest conversation: "Me" is the user and "Other party" is the other participant.
        Return a JSON object: topic is the current topic, suggestions is an array of 1–3 suggested next steps, answer is a suggested answer or null, todos is an array of action items with who and what, and decisions is an array of agreed decisions.
        Write all content in English. Limit suggestions to 1–3 items. Use only information present in the conversation. Return null when no suggested answer is appropriate, and empty strings or arrays for other fields without content. Do not invent information.
        """
        guard !relevantVocabulary.isEmpty else { return base }

        let terms = relevantVocabulary.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(base)

        User vocabulary matched in the current context:
        \(terms)
        When referring to these terms, preserve their exact spelling. Do not introduce information absent from the conversation.
        """
    }

    static func parse(_ raw: String) -> InsightResult? {
        JSONResponseParser.decode(InsightResult.self, from: raw)
    }
}
