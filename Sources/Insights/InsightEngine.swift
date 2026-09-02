import Foundation
import Observation

/// Drives AI meeting insights: it watches finalized conversation content, flattens it to
/// a prompt, calls the configured `InsightProvider`, and publishes an `InsightResult`
/// the UI renders. Owned by `CaptureCoordinator` alongside `store`/`translation`.
///
/// **Trigger model (speaker-switch / every-N-sentences).** The coordinator calls
/// `noteNewFinalContent` from its existing commit/seal hooks; the engine counts
/// finalized sentences and regenerates when a threshold is crossed or the speaker
/// changed. It never generates on volatile interim text — only on committed content.
///
/// **Coalescing (mirrors `TranslationBridge`).** While a generation is in flight, new
/// content doesn't queue up; it just sets a "dirty" flag, and exactly one more pass runs
/// afterward on the latest full transcript. So dense speech can't pile up requests or
/// burn quota — the model always works on the freshest snapshot and no more often than
/// one call at a time.
@MainActor
@Observable
final class InsightEngine {
    /// UI-facing lifecycle. `.error` carries a user-readable `LLMError`.
    enum State: Equatable {
        case idle            // nothing generated yet this meeting
        case generating      // a request is in flight
        case done            // `current` holds a fresh result
        case error(LLMError)
    }

    private(set) var current: InsightResult = .empty
    private(set) var state: State = .idle

    /// Injected settings — the single source of the provider + key. Read at call time so
    /// the user can configure mid-meeting and the next pass picks it up.
    private let settings: InsightSettings

    /// Sentences committed since the last generation, and the last speaker seen — the
    /// two signals that decide when to regenerate.
    private var sentencesSinceGen = 0
    private var lastSpeaker: Speaker?
    /// Regenerate after this many new finalized sentences (echoes the 6-sentence display
    /// cap so a full bubble ≈ one insight refresh).
    private let sentencesPerRefresh = 6

    /// Coalescing flags: whether a pass is running, and whether content changed during it.
    private var isGenerating = false
    private var dirtyDuringGen = false
    /// The freshest flattened transcript, captured on each note so the post-gen pass has
    /// the latest even if sections mutated meanwhile.
    private var latestTranscript = ""
    private var latestLanguage: CaptureCoordinator.MeetingLanguage = .english

    init(settings: InsightSettings) {
        self.settings = settings
    }

    /// Whether insights are configured (passthrough to settings) — the UI gate for
    /// showing cards vs. the "configure me" prompt.
    var isConfigured: Bool { settings.isConfigured }

    /// Reset for a new meeting (or on stop) — clear counters and the published result.
    func reset() {
        current = .empty
        state = .idle
        sentencesSinceGen = 0
        lastSpeaker = nil
        isGenerating = false
        dirtyDuringGen = false
        latestTranscript = ""
    }

    // MARK: - Live trigger

    /// Called from the coordinator whenever finalized content lands (a commit) or a turn
    /// seals (speaker switch). Decides whether it's time to regenerate and, if so, kicks
    /// a coalesced pass. No-op when insights aren't configured.
    func noteNewFinalContent(sections: [Section],
                             language: CaptureCoordinator.MeetingLanguage,
                             speaker: Speaker?) {
        guard settings.isConfigured else { return }

        latestLanguage = language
        latestTranscript = Self.flatten(sections: sections, language: language)
        guard !latestTranscript.isEmpty else { return }

        var shouldGen = false
        if let speaker, speaker != lastSpeaker, lastSpeaker != nil {
            shouldGen = true          // speaker switch — a natural insight boundary
        }
        if let speaker { lastSpeaker = speaker }
        sentencesSinceGen += 1
        if sentencesSinceGen >= sentencesPerRefresh { shouldGen = true }

        if shouldGen { triggerLive() }
    }

    /// Start a live pass, coalescing if one is already running.
    private func triggerLive() {
        sentencesSinceGen = 0
        if isGenerating { dirtyDuringGen = true; return }
        guard let provider = settings.makeProvider() else { return }
        isGenerating = true
        dirtyDuringGen = false
        state = .generating
        let transcript = latestTranscript
        let language = latestLanguage
        Task { @MainActor in
            await runPass(provider: provider, transcript: transcript, language: language)
            isGenerating = false
            // Coalesced: if content changed while we were busy, run exactly once more.
            if dirtyDuringGen, settings.isConfigured {
                dirtyDuringGen = false
                triggerLive()
            }
        }
    }

    /// Execute one generation and publish the result (or an error).
    private func runPass(provider: InsightProvider, transcript: String,
                         language: CaptureCoordinator.MeetingLanguage) async {
        do {
            let raw = try await provider.complete(
                system: Self.systemPrompt(language: language), user: transcript)
            if let result = Self.parse(raw) {
                if result != current { current = result }
                state = .done
            } else {
                state = .error(.badResponse)
            }
        } catch let e as LLMError {
            state = .error(e)
        } catch {
            state = .error(.network(error.localizedDescription))
        }
    }

    // MARK: - One-shot (history)

    /// Generate insights once for a finished meeting's flattened transcript (from
    /// `HistoryDetailView`). Returns the result so the caller can persist it, or throws
    /// an `LLMError` the UI can show. Independent of the live counters.
    func generateOnce(transcript: String,
                      language: CaptureCoordinator.MeetingLanguage) async throws -> InsightResult {
        guard let provider = settings.makeProvider() else { throw LLMError.notConfigured }
        guard !transcript.trimmed.isEmpty else { return .empty }
        let raw = try await provider.complete(
            system: Self.systemPrompt(language: language), user: transcript)
        guard let result = Self.parse(raw) else { throw LLMError.badResponse }
        return result
    }

    // MARK: - Refine (LLM second-pass over a finished meeting)

    /// In-flight state for the manual refine pass, so the header button/spinner can show
    /// batch progress. Separate from the live insight `state`.
    enum RefineState: Equatable {
        case idle
        case refining(done: Int, total: Int)
        case error(LLMError)
    }
    private(set) var refineState: RefineState = .idle

    /// One refined line, keyed back to its `orderIndex` (`i`). `source`/`target` may be
    /// nil if the model chose not to change that field.
    struct RefineLine: Codable { let i: Int; let source: String?; let target: String? }
    /// A glossary entry: the source-language term and its agreed Chinese (or "keep原词").
    struct GlossaryTerm: Codable, Equatable { let term: String; let zh: String }
    /// The parsed JSON of one batch.
    private struct RefineBatch: Codable { let glossary: [GlossaryTerm]?; let lines: [RefineLine]? }

    /// The result of a full refine: refined text keyed by `orderIndex`, plus the merged
    /// glossary (as JSON) to cache for next time.
    struct RefineOutcome {
        var byIndex: [Int: RefineLine]
        var glossaryJSON: String?
    }

    // Batch size for the refine pass. Kept SMALL on purpose: refine asks the model to
    // rewrite every line, so per-request OUTPUT is large — a big batch (e.g. 6000 chars)
    // produced 6000+ completion tokens and tipped the upstream into HTTP 500, silently
    // dropping the whole batch. Diagnostics showed ~8 lines / ~1500 chars stays well under
    // limits and succeeds reliably. Line count is the primary cap; chars is the safety valve.
    private let refineBatchLines = 8
    private let refineBatchMaxChars = 1500

    func resetRefine() { refineState = .idle }

    /// Refine a finished meeting's transcript: conservatively clean each line's ORIGINAL
    /// text (filler words / typos — never rewriting meaning) and redo each translation
    /// with full context + a running glossary. Batched serially over long meetings, each
    /// batch carrying the previous batch's tail as context and the accumulated glossary so
    /// terminology stays consistent. Returns refined text keyed by `orderIndex` (unmatched
    /// lines are simply absent → the caller keeps their originals). Throws `LLMError`.
    func refineOnce(lines rawLines: [TranscriptLine],
                    language: CaptureCoordinator.MeetingLanguage,
                    priorGlossaryJSON: String?) async throws -> RefineOutcome {
        guard let provider = settings.makeProvider() else {
            refineState = .error(.notConfigured); throw LLMError.notConfigured
        }
        let lines = rawLines
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { !$0.sourceText.trimmed.isEmpty }
        guard !lines.isEmpty else { refineState = .idle; return RefineOutcome(byIndex: [:], glossaryJSON: priorGlossaryJSON) }

        let batches = Self.batch(lines, maxLines: refineBatchLines, maxChars: refineBatchMaxChars)
        var glossary = Self.decodeGlossary(priorGlossaryJSON)
        var byIndex: [Int: RefineLine] = [:]
        var succeeded = 0
        var lastError: LLMError? = nil

        refineState = .refining(done: 0, total: batches.count)
        for (bi, batch) in batches.enumerated() {
            // Carry the last 2 lines of the previous batch as read-only context so
            // cross-batch translation stays coherent (not re-refined, just context).
            let context = bi > 0 ? Array(batches[bi - 1].suffix(2)) : []
            let user = Self.refineInput(batch: batch, context: context)
            // PER-BATCH fault tolerance: one batch failing (timeout, rate-limit, unparseable
            // JSON — more likely on noisy Chinese ASR) must NOT discard the whole meeting's
            // work. A failed batch is skipped (its lines keep their originals); we only fail
            // the whole pass if EVERY batch failed. This matches the additive design.
            do {
                let raw = try await provider.complete(
                    system: Self.refinePrompt(language: language, glossary: glossary),
                    user: user)
                if let parsed = Self.parseRefine(raw) {
                    for line in parsed.lines ?? [] { byIndex[line.i] = line }
                    glossary = Self.mergeGlossary(glossary, parsed.glossary ?? [])
                    succeeded += 1
                } else {
                    lastError = .badResponse
                }
            } catch let e as LLMError {
                lastError = e
            } catch {
                lastError = .network(error.localizedDescription)
            }
            refineState = .refining(done: bi + 1, total: batches.count)
        }

        // Every batch failed → surface the error and don't claim a refinement.
        if succeeded == 0, let e = lastError {
            refineState = .error(e); throw e
        }
        refineState = .idle
        return RefineOutcome(byIndex: byIndex, glossaryJSON: Self.encodeGlossary(glossary))
    }

    // MARK: - Refine helpers

    /// Split lines into batches bounded by line count AND a char budget (whichever hits
    /// first), so a run of very long lines still produces a manageable request.
    private static func batch(_ lines: [TranscriptLine], maxLines: Int,
                              maxChars: Int) -> [[TranscriptLine]] {
        var out: [[TranscriptLine]] = []
        var cur: [TranscriptLine] = []
        var chars = 0
        for l in lines {
            let c = l.sourceText.count
            if !cur.isEmpty && (cur.count >= maxLines || chars + c > maxChars) {
                out.append(cur); cur = []; chars = 0
            }
            cur.append(l); chars += c
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Build the numbered input for one batch. Each line is labeled with its GLOBAL
    /// `orderIndex` so the model's `i` maps back unambiguously; a `[上文]` block gives
    /// read-only continuity from the previous batch.
    private static func refineInput(batch: [TranscriptLine],
                                    context: [TranscriptLine]) -> String {
        var s = ""
        if !context.isEmpty {
            s += "[上文（仅供参考，不要输出）]\n"
            for l in context {
                s += "\(l.isMine ? "我" : "对方")：\(l.sourceText.trimmed)\n"
            }
            s += "\n[需要优化的内容]\n"
        }
        for l in batch {
            s += "[\(l.orderIndex)] \(l.isMine ? "我" : "对方")：\(l.sourceText.trimmed)\n"
        }
        return s
    }

    /// The refine system prompt. English meetings: conservative source cleanup + retranslate.
    /// Chinese meetings: the source IS the caption, and 中英混杂 ASR is often badly garbled
    /// (no punctuation, filler/repetition, English terms mis-transliterated), so the Chinese
    /// branch is deliberately MORE active — punctuate, de-duplicate, and restore garbled
    /// English terms — while holding a hard no-fabrication line. Contains "json" for
    /// json_object mode.
    static func refinePrompt(language: CaptureCoordinator.MeetingLanguage,
                             glossary: [GlossaryTerm]) -> String {
        let glossaryBlock: String = glossary.isEmpty ? "（暂无术语表）"
            : glossary.map { "- \($0.term) → \($0.zh)" }.joined(separator: "\n")

        if language.needsTranslation {
            // English (or other foreign) meeting → clean original conservatively + retranslate.
            return """
            你是一个会议记录校对助手。下面是一段会议逐句记录，每行以 [序号] 开头，格式为 \
            “[序号] 说话人：原文”。请你逐行优化，并**只**返回一个 JSON 对象（不要解释、不要 markdown）。

            术语表（请严格遵循，技术词可保留英文原词）：
            \(glossaryBlock)

            返回 JSON 结构：
            {
              "glossary": [{"term":"原词","zh":"建议中文或‘保留原词’"}],
              "lines": [{"i": 序号, "source": "优化后的原文", "target": "优化后的中文译文"}]
            }

            硬性规则：
            - 每一行都必须返回，且 "i" 必须与输入的 [序号] 完全一致，不得漏行、不得改变顺序、不得合并。
            - **source（原文校对）**：只做保守清理——删除口水词（呃、嗯、uh、um 等）、修正明显的识别错字、补全标点。\
            严禁增加或删除任何事实内容，严禁改写句子含义，严禁翻译，保持原文所用语言。
            - **target（译文）**：结合上下文与术语表，把该行原文重新翻译成通顺、准确的简体中文。
            - glossary：把你在本段发现的专有名词/技术术语补充进去（原词→建议中文或“保留原词”）。
            - 只依据原文，不要臆测未出现的内容。
            """
        }

        // Chinese-primary meeting → the source IS the caption; actively tidy garbled 中英混杂.
        // Output is SOURCE-ONLY (no target — for Chinese, target == source, so echoing it
        // would double the output tokens and was tipping large batches into HTTP 500). The
        // prompt is kept lean for the same reason. The caller mirrors source→target.
        return """
        你是中文会议记录整理编辑。下面每行以 [序号] 开头，格式为“[序号] 说话人：原文”。识别质量差：\
        常无断句、有口水词和重复、夹杂的英文词/人名被音译成乱码。请逐行整理成通顺可读、忠实原意的中文。\
        **只**返回一个 JSON（不要解释、不要 markdown）。

        术语表（英文技术词请用正确英文写法）：
        \(glossaryBlock)

        返回：{"glossary":[{"term":"识别乱码","zh":"正确写法"}],"lines":[{"i":序号,"source":"整理后的中文"}]}

        要求：
        - 每行都要返回，"i" 与输入 [序号] 完全一致，不漏行、不改顺序、不合并。
        - 断句补标点；删口水词（呃、嗯、就是、那个等）和明显重复。
        - 把音译乱码的英文术语/人名结合上下文还原成正确英文（如 onbording→onboarding、\
        complinice→compliance、romination→remediation）；不确定就保留原样。
        - 忠实底线：不虚构原文没有的事实、观点、数字、人名；听不清宁可保留模糊，不要脑补。
        - glossary：把你还原的英文术语/人名补进去。
        """
    }

    /// Tolerant parse of a refine batch (same fence/brace salvaging as `parse`).
    private static func parseRefine(_ raw: String) -> RefineBatch? {
        let cleaned = stripFence(raw)
        if let data = cleaned.data(using: .utf8),
           let r = try? JSONDecoder().decode(RefineBatch.self, from: data) { return r }
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"), start < end,
           let data = String(cleaned[start...end]).data(using: .utf8),
           let r = try? JSONDecoder().decode(RefineBatch.self, from: data) { return r }
        return nil
    }

    private static func decodeGlossary(_ json: String?) -> [GlossaryTerm] {
        guard let json, let data = json.data(using: .utf8),
              let g = try? JSONDecoder().decode([GlossaryTerm].self, from: data) else { return [] }
        return g
    }
    private static func encodeGlossary(_ g: [GlossaryTerm]) -> String? {
        guard !g.isEmpty, let data = try? JSONEncoder().encode(g) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    /// Merge new terms into the running glossary, deduping by term (case-insensitive),
    /// newest definition wins.
    private static func mergeGlossary(_ base: [GlossaryTerm],
                                      _ add: [GlossaryTerm]) -> [GlossaryTerm] {
        var map = [String: GlossaryTerm]()
        var order: [String] = []
        for t in base + add {
            let key = t.term.lowercased().trimmed
            guard !key.isEmpty else { continue }
            if map[key] == nil { order.append(key) }
            map[key] = t
        }
        return order.compactMap { map[$0] }
    }

    // MARK: - Prompt + parsing

    /// Flatten sections to a "谁：说了什么" script the LLM reads. Uses the SOURCE text
    /// (the recognized original) so the model reasons over the ground-truth words:
    /// Chinese meetings feed Chinese, English meetings feed English (the model is told to
    /// answer in Chinese regardless). Mirrors how `TranscriptExporter` walks sections.
    static func flatten(sections: [Section],
                        language: CaptureCoordinator.MeetingLanguage) -> String {
        var lines: [String] = []
        for s in sections {
            let text = s.sourceText.trimmed
            guard !text.isEmpty else { continue }
            let who = s.speaker == .mine ? "我" : "对方"
            lines.append("\(who)：\(text)")
        }
        return lines.joined(separator: "\n")
    }

    /// Flatten persisted history lines the same way (for the one-shot path).
    static func flatten(lines: [TranscriptLine]) -> String {
        lines.sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { l in
                let t = l.sourceText.trimmed
                guard !t.isEmpty else { return nil }
                return "\(l.isMine ? "我" : "对方")：\(t)"
            }
            .joined(separator: "\n")
    }

    /// The system prompt: role, the exact JSON schema (which doubles as `InsightResult`),
    /// and hard rules. Contains the literal word "json" so json_object mode is satisfied
    /// for Qwen/DeepSeek. Always instructs Chinese output regardless of meeting language.
    static func systemPrompt(language: CaptureCoordinator.MeetingLanguage) -> String {
        """
        你是一个实时会议助手。下面是一段正在进行的会议对话记录（“我”是使用者本人，“对方”是其他参会者）。\
        请你分析当前对话，帮助“我”更好地推进会议。

        请**只**返回一个 JSON 对象（不要任何解释、不要 markdown 代码块），字段如下：
        {
          "topic": "用一两句话概括当前正在讨论的话题",
          "suggestions": ["给“我”的下一步建议或可以追问的问题", "..."],
          "answer": "如果“对方”刚刚提出了一个问题，这里给出一段可参考的回答草稿；如果没有人提问，则为空字符串",
          "todos": [{"who": "负责人（我/对方/某人名）", "what": "需要做的事"}],
          "decisions": ["会议已经达成的决定"]
        }

        规则：
        - 所有输出内容一律使用**简体中文**。
        - 严格输出上述 JSON 结构；没有内容的字段返回空数组或空字符串，不要编造。
        - suggestions 控制在 1-3 条，简短、可执行。
        - 只依据对话中真实出现的信息，不要臆测。
        """
    }

    /// Parse the model's raw text into `InsightResult`, tolerating a stray code fence or
    /// surrounding prose by extracting the outermost JSON object. Returns nil if no valid
    /// object is found, so the caller degrades gracefully instead of crashing.
    static func parse(_ raw: String) -> InsightResult? {
        let cleaned = stripFence(raw)
        if let data = cleaned.data(using: .utf8),
           let r = try? JSONDecoder().decode(InsightResult.self, from: data) {
            return r
        }
        // Fallback: grab the first {...} block.
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"), start < end {
            let slice = String(cleaned[start...end])
            if let data = slice.data(using: .utf8),
               let r = try? JSONDecoder().decode(InsightResult.self, from: data) {
                return r
            }
        }
        return nil
    }

    /// Strip a ```json … ``` fence if the model wrapped its output despite instructions.
    private static func stripFence(_ s: String) -> String {
        var t = s.trimmed
        if t.hasPrefix("```") {
            // Drop the first line (``` or ```json) and a trailing ```.
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if let r = t.range(of: "```", options: .backwards) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmed
    }
}
