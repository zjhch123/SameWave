import Foundation
import Observation

@MainActor
@Observable
final class TranscriptRefiner {
    enum State: Equatable {
        case idle
        case refining(done: Int, total: Int)
        case error(LLMError)
    }

    struct RefinedLine: Decodable {
        let i: Int
        let source: String
        let target: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            i = try container.decode(Int.self, forKey: .i)
            source = TranscriptRefiner.strippingSpeakerPrefix(
                from: try container.decode(String.self, forKey: .source)
            )
            guard container.contains(.target) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.target,
                    .init(codingPath: container.codingPath, debugDescription: "target is required")
                )
            }
            target = try container.decodeIfPresent(String.self, forKey: .target)
                .map { TranscriptRefiner.strippingSpeakerPrefix(from: $0) }
        }

        private enum CodingKeys: String, CodingKey {
            case i, source, target
        }
    }

    struct GlossaryTerm: Codable, Equatable {
        let term: String
        let target: String
    }

    struct Outcome {
        var byIndex: [Int: RefinedLine]
        var glossaryJSON: String?
    }

    private struct BatchResponse: Decodable {
        let glossary: [GlossaryTerm]
        let lines: [RefinedLine]
    }

    private let providerFactory: () -> (any LLMProvider)?
    private let settings: AISettings
    private let vocabularySettings: SpeechVocabularySettings
    private let batchLineLimit = 8
    private let batchCharacterLimit = 1_500
    private(set) var state: State = .idle
    private var runID = UUID()

    init(settings: AISettings, vocabularySettings: SpeechVocabularySettings,
         providerFactory: (() -> (any LLMProvider)?)? = nil) {
        self.settings = settings
        self.providerFactory = providerFactory ?? { settings.makeProvider() }
        self.vocabularySettings = vocabularySettings
    }

    func cancel() {
        runID = UUID()
        state = .idle
    }

    func refine(lines rawLines: [TranscriptLine], languagePair: MeetingLanguagePair,
                priorGlossaryJSON: String?) async throws -> Outcome {
        let expectedRunID = UUID()
        runID = expectedRunID
        guard settings.isEnabled else {
            state = .error(.disabled)
            throw LLMError.disabled
        }
        guard let provider = providerFactory() else {
            state = .error(.notConfigured)
            throw LLMError.notConfigured
        }
        let lines = rawLines
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { !$0.sourceText.trimmed.isEmpty }
        guard !lines.isEmpty else {
            state = .idle
            return Outcome(byIndex: [:], glossaryJSON: priorGlossaryJSON)
        }

        let batches = Self.makeBatches(
            lines,
            maxLines: batchLineLimit,
            maxCharacters: batchCharacterLimit
        )
        let configuredVocabulary = vocabularySettings.phrases
        var glossary = Self.decodeGlossary(priorGlossaryJSON)
        var refinedByIndex: [Int: RefinedLine] = [:]
        var successCount = 0
        var lastError: LLMError = .schemaViolation

        state = .refining(done: 0, total: batches.count)
        for (index, batch) in batches.enumerated() {
            try Task.checkCancellation()
            guard runID == expectedRunID else { throw CancellationError() }
            let context = index > 0 ? Array(batches[index - 1].suffix(2)) : []
            do {
                let raw = try await provider.complete(
                    system: Self.prompt(
                        languagePair: languagePair,
                        configuredVocabulary: configuredVocabulary,
                        glossary: glossary
                    ),
                    user: Self.input(batch: batch, context: context),
                    schema: Self.responseSchema(needsTranslation: languagePair.needsTranslation)
                )
                try Task.checkCancellation()
                guard runID == expectedRunID else { throw CancellationError() }
                guard let response = JSONResponseParser.decode(BatchResponse.self, from: raw) else {
                    lastError = .schemaViolation
                    state = .refining(done: index + 1, total: batches.count)
                    continue
                }
                let indices = Set(batch.map(\.orderIndex))
                let validLines = response.lines.filter { indices.contains($0.i) }
                guard !validLines.isEmpty else {
                    lastError = .schemaViolation
                    state = .refining(done: index + 1, total: batches.count)
                    continue
                }
                for line in validLines { refinedByIndex[line.i] = line }
                glossary = Self.mergeGlossary(glossary, response.glossary)
                successCount += 1
            } catch is CancellationError {
                if runID == expectedRunID { state = .idle }
                throw CancellationError()
            } catch let error as LLMError {
                lastError = error
            } catch {
                lastError = .network(error.localizedDescription)
            }
            if runID == expectedRunID {
                state = .refining(done: index + 1, total: batches.count)
            }
        }

        try Task.checkCancellation()
        guard runID == expectedRunID else { throw CancellationError() }
        guard successCount > 0 else {
            state = .error(lastError)
            throw lastError
        }
        state = .idle
        return Outcome(
            byIndex: refinedByIndex,
            glossaryJSON: Self.encodeGlossary(glossary)
        )
    }

    static func makeBatches(_ lines: [TranscriptLine], maxLines: Int,
                            maxCharacters: Int) -> [[TranscriptLine]] {
        var batches: [[TranscriptLine]] = []
        var current: [TranscriptLine] = []
        var characters = 0
        for line in lines {
            let count = line.sourceText.count
            if !current.isEmpty && (current.count >= maxLines || characters + count > maxCharacters) {
                batches.append(current)
                current = []
                characters = 0
            }
            current.append(line)
            characters += count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private static func input(batch: [TranscriptLine], context: [TranscriptLine]) -> String {
        var value = ""
        if !context.isEmpty {
            value += "[Previous context (reference only; do not include in output)]\n"
            for line in context {
                value += "\(line.isMine ? "Me" : "Other party"): \(line.sourceText.trimmed)\n"
            }
            value += "\n[Text to refine]\n"
        }
        for line in batch {
            value += "[\(line.orderIndex)] \(line.isMine ? "Me" : "Other party"): \(line.sourceText.trimmed)\n"
        }
        return value
    }

    /// The prompt labels input lines so the model can preserve speaker context. Some
    /// models echo that label into `source` or `target`; strip only an anchored label
    /// followed by a colon so ordinary first-person sentences remain untouched.
    nonisolated static func strippingSpeakerPrefix(from value: String) -> String {
        var result = value.trimmed
        let labels = ["Other party", "对方", "Me", "我"]

        while true {
            var removed = false
            for label in labels {
                guard let labelRange = result.range(
                    of: label,
                    options: [.anchored, .caseInsensitive]
                ) else { continue }
                var remainder = result[labelRange.upperBound...]
                while remainder.first?.isWhitespace == true { remainder.removeFirst() }
                guard remainder.first == ":" || remainder.first == "：" else { continue }
                remainder.removeFirst()
                result = String(remainder).trimmed
                removed = true
                break
            }
            if !removed { return result }
        }
    }

    static func prompt(languagePair: MeetingLanguagePair,
                       configuredVocabulary: [String],
                       glossary: [GlossaryTerm]) -> String {
        let configuredVocabularyText = configuredVocabulary.isEmpty
            ? "(No user vocabulary)"
            : configuredVocabulary.map { "- \($0)" }.joined(separator: "\n")
        let glossaryText = glossary.isEmpty
            ? "(No previous refinement glossary)"
            : glossary.map { "- \($0.term) → \($0.target)" }.joined(separator: "\n")
        let source = languagePair.source.label
        let target = languagePair.target.label
        if languagePair.needsTranslation {
            return """
            You are a meeting transcript proofreader and translator. The source language is \(source) and the target language is \(target). Conservatively clean up each source line and translate it again.
            Return a JSON object: glossary is an array of terms with term and target; lines is an array of results with the input index i, corrected source, and the \(target) translation in target.

            User vocabulary (use only when the conversation matches; preserve exact spelling in source and do not insert terms absent from the conversation):
            \(configuredVocabularyText)

            Previous refinement glossary (prefer these translation mappings over your own choices):
            \(glossaryText)

            Return every line with its original index i. Do not merge or reorder lines. source and target must contain only the text, without speaker labels such as "Me" or "Other party". source must remain in \(source): only remove filler words, correct obvious recognition errors using context and user vocabulary, and add punctuation. Do not add or remove facts or change meaning. target must be in \(target), faithful to the source and glossary. Keep brands, products, personal names, and acronyms in their original form when no established translation exists.
            """
        }
        return """
        You are an editor of \(source) meeting transcripts. The source and target languages are the same; do not translate. Add punctuation and remove filler words and obvious repetition line by line.
        Return a JSON object: glossary is an array of terms with term and target; lines is an array of results with the input index i, edited source, and target set to null.

        User vocabulary (use only when the conversation matches; preserve exact spelling in source and do not insert terms absent from the conversation):
        \(configuredVocabularyText)

        Previous refinement glossary:
        \(glossaryText)

        Return every line with its original index i. Do not merge or reorder lines. source must contain only the text, without speaker labels such as "Me" or "Other party". source must remain in \(source); use the exact spelling of user vocabulary only where the context matches. Return null for target. Leave uncertain content unchanged. Do not invent facts, opinions, numbers, or names.
        """
    }

    static func responseSchema(needsTranslation: Bool) -> LLMResponseSchema {
        return LLMResponseSchema(
            name: needsTranslation ? "translated_transcript_batch" : "transcript_batch",
            schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "glossary": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "term": .object(["type": .string("string")]),
                                "target": .object(["type": .string("string")])
                            ]),
                            "required": .array([.string("term"), .string("target")]),
                            "additionalProperties": .bool(false)
                        ])
                    ]),
                    "lines": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "i": .object(["type": .string("integer")]),
                                "source": .object(["type": .string("string")]),
                                "target": .object([
                                    "type": .string(needsTranslation ? "string" : "null")
                                ])
                            ]),
                            "required": .array([
                                .string("i"), .string("source"), .string("target")
                            ]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ]),
                "required": .array([.string("glossary"), .string("lines")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    private static func decodeGlossary(_ json: String?) -> [GlossaryTerm] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GlossaryTerm].self, from: data)) ?? []
    }

    private static func encodeGlossary(_ glossary: [GlossaryTerm]) -> String? {
        guard !glossary.isEmpty, let data = try? JSONEncoder().encode(glossary) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func mergeGlossary(_ existing: [GlossaryTerm],
                                      _ new: [GlossaryTerm]) -> [GlossaryTerm] {
        var terms: [String: GlossaryTerm] = [:]
        var order: [String] = []
        for term in existing + new {
            let key = term.term.lowercased().trimmed
            guard !key.isEmpty else { continue }
            if terms[key] == nil { order.append(key) }
            terms[key] = term
        }
        return order.compactMap { terms[$0] }
    }
}
