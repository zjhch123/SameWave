import Foundation
import Observation

/// Owns display turns independently of cumulative recognition. Continuous overlap
/// retains each speaker's paragraph; speech returning after an interruption opens
/// a later one, while corrections retain the existing words' ownership.
@MainActor
@Observable
final class CaptionStore {
    private(set) var sections: [Section] = []

    /// DISPLAY cap: a single-speaker section seals and opens a fresh one once it has
    /// accumulated `maxSentencesPerSection` sentences of source, checked before the
    /// next utterance (interim or final). Governs bubble size ONLY; translation context is the separate
    /// sentence-scoped window below, so sealing a bubble never discards the running
    /// paragraph's context.
    private let maxSentencesPerSection = 6

    private let contextWindowSentences = 5
    private let contextWindowMaxChars = 240
    private var nextId = 0
    private var openSections: [Speaker: Int] = [:]
    private var hypotheses: [Speaker: SpeechHypothesis] = [:]
    /// Recognition activity, not callback arrival alone: corrections do not extend
    /// it. A one-second gap in added words distinguishes a return from dense overlap.
    private let turnInactivity: Duration = .seconds(1)
    private var lastGrowth: [Speaker: ContinuousClock.Instant] = [:]

    // MARK: - Lookup

    func section(id: Int) -> Section? { sections.first { $0.id == id } }
    private func indexOf(id: Int) -> Int? { sections.firstIndex { $0.id == id } }
    private func mutate(id: Int, _ body: (inout Section) -> Void) {
        guard let i = indexOf(id: id) else { return }
        body(&sections[i])
    }
    var hasContent: Bool { !sections.isEmpty }

    /// The most recent context window for `speaker` (chronological, newest last),
    /// bounded by sentence count and a char budget — frozen onto a section at open.
    private func contextSnapshot(for speaker: Speaker) -> [String] {
        let sentences = sections.filter { $0.speaker == speaker }.flatMap { section in
            section.committedSource + (section.interimSource.isEmpty ? [] : [section.interimSource])
        }
        var picked: [String] = []
        var chars = 0
        for sentence in sentences.reversed() {
            if picked.count >= contextWindowSentences { break }
            if chars + sentence.count > contextWindowMaxChars && !picked.isEmpty { break }
            picked.append(sentence)
            chars += sentence.count
        }
        return picked.reversed()
    }

    // MARK: - Source sections

    private func isGrowing(_ speaker: Speaker, at time: ContinuousClock.Instant) -> Bool {
        guard let last = lastGrowth[speaker] else { return false }
        return last.duration(to: time) < turnInactivity
    }

    private func takeTurn(_ speaker: Speaker, at time: ContinuousClock.Instant) -> (opened: Int, sealed: [Int]) {
        if let id = openSections[speaker], let current = section(id: id),
           current.committedSource.count < maxSentencesPerSection,
           sections.last?.id == id || isGrowing(speaker, at: time) {
            return (id, [])
        }
        // Close idle or finalized contributions, retaining unfinished continuous
        // overlap. The recognizer hypothesis survives either kind of display seal.
        let sealed = openSections.filter { owner, _ in
            owner == speaker || !isGrowing(owner, at: time) || hypotheses[owner] == nil
        }
        for (owner, id) in sealed {
            mutate(id: id) { $0.contentState = .sealed }
            openSections.removeValue(forKey: owner)
        }
        let id = nextId
        nextId += 1
        var section = Section(id: id, speaker: speaker)
        section.priorContext = contextSnapshot(for: speaker)
        sections.append(section)
        openSections[speaker] = id
        return (id, Array(sealed.values))
    }

    /// Apply one cumulative ASR snapshot. Only added speech can acquire the floor;
    /// corrections retain their words' section IDs, including after sealing.
    /// Returns every affected section for native captions and translation scheduling.
    @discardableResult
    func updateSource(_ text: String, speaker: Speaker, isFinal: Bool,
                      at time: ContinuousClock.Instant = .now) -> [Int] {
        guard !text.trimmed.isEmpty else { return [] }
        let previous = hypotheses[speaker] ?? SpeechHypothesis()
        var words = previous.revising(text)
        guard !words.isEmpty else { return [] }
        var changed = Set(previous.words.compactMap(\.sectionID))
        if words.contains(where: { $0.sectionID == nil }) {
            let turn = takeTurn(speaker, at: time)
            changed.formUnion(turn.sealed)
            lastGrowth[speaker] = time
            for index in words.indices where words[index].sectionID == nil {
                words[index].sectionID = turn.opened
            }
        }
        changed.formUnion(words.compactMap(\.sectionID))
        for id in changed {
            // A speaker switch can also seal the other speaker's section. Its
            // hypothesis remains owned by that recognizer and is not rewritten here.
            guard section(id: id)?.speaker == speaker else { continue }
            let fragment = words.filter { $0.sectionID == id }.map(\.text).joined().trimmed
            mutate(id: id) { section in
                if isFinal && !fragment.isEmpty { section.committedSource.append(fragment) }
                section.interimSource = isFinal ? "" : fragment
            }
        }
        hypotheses[speaker] = isFinal ? nil : SpeechHypothesis(words: words)
        if isFinal, let id = openSections[speaker], sections.last?.id != id {
            mutate(id: id) { $0.contentState = .sealed }
            openSections.removeValue(forKey: speaker)
            changed.insert(id)
        }
        // A recognizer can retract an entire fragment. Remove its display row and
        // identity so a late translation cannot bring the deleted words back.
        sections.removeAll { changed.contains($0.id) && $0.sourceText.isEmpty }
        openSections = openSections.filter { section(id: $0.value) != nil }
        return changed.sorted()
    }

    /// Pause/end promotes each pending fragment once, including those belonging to
    /// already sealed turns. Normal speaker switches never finalize another ASR stream.
    @discardableResult
    func endTurn(_ speaker: Speaker) -> [Int] {
        var changed = Set(hypotheses.removeValue(forKey: speaker)?.words.compactMap(\.sectionID) ?? [])
        if let id = openSections.removeValue(forKey: speaker) { changed.insert(id) }
        lastGrowth.removeValue(forKey: speaker)
        for id in changed {
            mutate(id: id) { section in
                section.contentState = .sealed
                if !section.interimSource.isEmpty { section.committedSource.append(section.interimSource) }
                section.interimSource = ""
            }
        }
        return changed.sorted()
    }

    // MARK: - Translation (Rule B — independent axis)

    /// Source identity, rather than sealing or duplicate callbacks, creates work.
    func beginTranslation(id: Int) -> Int? {
        guard let index = indexOf(id: id) else { return nil }
        let source = sections[index].sourceText
        guard !source.isEmpty,
              source != sections[index].requestedSource || sections[index].translationState == .failed else {
            return nil
        }
        sections[index].requestedSource = source
        sections[index].generation += 1
        sections[index].translationState = .translating
        return sections[index].generation
    }

    /// Publish useful progress while newer source is queued, without ever replacing
    /// a newer displayed result with an older completion. Only current source is done.
    func applyTranslation(_ translated: String, id: Int, generation: Int) {
        mutate(id: id) { section in
            guard generation > section.translatedGeneration, generation <= section.generation else { return }
            let text = translated.trimmed
            guard !text.isEmpty else {
                if generation == section.generation { section.translationState = .failed }
                return
            }
            section.targetText = text
            section.translatedGeneration = generation
            if generation == section.generation { section.translationState = .done }
        }
    }

    func failTranslation(id: Int, generation: Int) {
        mutate(id: id) { section in
            guard generation == section.generation else { return }
            section.translationState = .failed
        }
    }

    /// Same-language meetings display the recognized source directly.
    func setNativeCaption(id: Int) {
        mutate(id: id) { s in
            s.targetText = s.sourceText
            s.translationState = .done
        }
    }

    // MARK: - Helpers

    func clear() {
        sections.removeAll()
        openSections.removeAll()
        hypotheses.removeAll()
        lastGrowth.removeAll()
        nextId = 0
    }

    /// Rebuild the transcript from a persisted meeting so a resumed / recovered
    /// session shows its earlier content and can keep recording into it. Every
    /// restored section comes back sealed. Missing translations are failed rather
    /// than pending work; both speakers start idle so the next spoken word opens a fresh
    /// section. Crucially each section keeps its ORIGINAL `sectionId`, and `nextId`
    /// resumes past the max — so continued incremental autosaves upsert the same rows
    /// instead of duplicating them, and new sections never collide with old ids.
    func restore(sections restored: [(id: Int, speaker: Speaker, source: String,
                                      target: String, startedAt: Date)]) {
        sections.removeAll()
        openSections.removeAll()
        hypotheses.removeAll()
        lastGrowth.removeAll()
        var maxId = -1
        for r in restored {
            var s = Section(id: r.id, speaker: r.speaker)
            s.contentState = .sealed
            s.translationState = r.target.trimmed.isEmpty ? .failed : .done
            let src = r.source.trimmed
            if !src.isEmpty { s.committedSource = [src] }
            s.targetText = r.target
            s.startedAt = r.startedAt
            sections.append(s)
            maxId = max(maxId, r.id)
        }
        nextId = maxId + 1
    }
}
