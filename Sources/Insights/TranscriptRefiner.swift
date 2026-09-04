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

    private let settings: InsightSettings
    private let vocabularySettings: SpeechVocabularySettings
    private let batchLineLimit = 8
    private let batchCharacterLimit = 1_500
    private(set) var state: State = .idle
    private var runID = UUID()

    init(settings: InsightSettings, vocabularySettings: SpeechVocabularySettings) {
        self.settings = settings
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
        guard let provider = settings.makeProvider() else {
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
            value += "[上文（仅供参考，不要输出）]\n"
            for line in context {
                value += "\(line.isMine ? "我" : "对方")：\(line.sourceText.trimmed)\n"
            }
            value += "\n[需要优化的内容]\n"
        }
        for line in batch {
            value += "[\(line.orderIndex)] \(line.isMine ? "我" : "对方")：\(line.sourceText.trimmed)\n"
        }
        return value
    }

    /// The prompt labels input lines so the model can preserve speaker context. Some
    /// models echo that label into `source` or `target`; strip only an anchored label
    /// followed by a colon so ordinary sentences such as "我觉得…" remain untouched.
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
            ? "（暂无用户词表）"
            : configuredVocabulary.map { "- \($0)" }.joined(separator: "\n")
        let glossaryText = glossary.isEmpty
            ? "（暂无上次优化术语表）"
            : glossary.map { "- \($0.term) → \($0.target)" }.joined(separator: "\n")
        let source = languagePair.source.label
        let target = languagePair.target.label
        if languagePair.needsTranslation {
            return """
            你是会议记录校对与翻译助手。源语言是\(source)，目标语言是\(target)。请逐行保守清理原文并重新翻译。
            输出必须是一个 JSON 对象：glossary 是术语数组，每项包含 term 和 target；lines 是逐行结果数组，每项包含输入序号 i、校对后的 source 和\(target)译文 target。

            用户词表（仅在对话内容匹配时使用；source 采用词条的精确拼写，不得强行植入未出现的词）：
            \(configuredVocabularyText)

            上次优化术语表（翻译映射优先于自行判断）：
            \(glossaryText)

            每行都必须返回，i 与输入序号一致，不得合并或改序。source 和 target 只包含正文，不要重复“我/对方”等说话人标签。source 必须保持\(source)，只删口水词、根据上下文和用户词表修正明显识别错误并补标点；不增删事实，不改写含义。target 必须使用\(target)，忠实原文和术语表；品牌、产品、人名和缩写没有既定翻译时保留原文。
            """
        }
        return """
        你是\(source)会议记录整理编辑。源语言和目标语言相同，不要翻译。请逐行补标点、删口水词和明显重复。
        输出必须是一个 JSON 对象：glossary 是术语数组，每项包含 term 和 target；lines 是逐行结果数组，每项包含输入序号 i、整理后的 source 和值为 null 的 target。

        用户词表（仅在对话内容匹配时使用；source 采用词条的精确拼写，不得强行植入未出现的词）：
        \(configuredVocabularyText)

        上次优化术语表：
        \(glossaryText)

        每行都必须返回，i 与输入序号一致，不得合并或改序。source 只包含正文，不要重复“我/对方”等说话人标签。source 必须保持\(source)，只在上下文匹配时采用用户词表的精确拼写，target 返回 null；不确定的内容保留原样，不得虚构事实、观点、数字或人名。
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
