import Foundation
import Observation

/// Owns source sections and translation progress on the main actor. Each speaker's
/// unfinished utterance retains its section across overlap; new utterances are
/// ordered by their first observed ASR result, without waiting for the other stream.
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

    /// TRANSLATION context window: how many of a speaker's preceding sentences are
    /// frozen onto a new section as leading context, and a char budget to bound the
    /// combined translation input's latency. Independent of the display cap.
    private let contextWindowSentences = 5
    private let contextWindowMaxChars = 240
    /// Rolling last-N committed sentences per speaker, independent of section
    /// boundaries — the source of each new section's `priorContext` snapshot.
    private var recentSentences: [Speaker: [String]] = [:]

    private var nextId = 0
    private var openSections: [Speaker: Int] = [:]

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
        var picked: [String] = []
        var chars = 0
        for sentence in (recentSentences[speaker] ?? []).reversed() {   // newest → oldest
            if picked.count >= contextWindowSentences { break }
            if chars + sentence.count > contextWindowMaxChars && !picked.isEmpty { break }
            picked.append(sentence)
            chars += sentence.count
        }
        return picked.reversed()   // back to chronological order
    }

    // MARK: - Source sections

    /// Revisions and finals belong to the speaker's unfinished utterance, even if
    /// the other speaker has opened a later section. Only a new utterance can split.
    private func sectionForUtterance(_ speaker: Speaker) -> (sectionId: Int, sealed: Int?) {
        var sealed: Int?
        if let id = openSections[speaker], let current = section(id: id) {
            if !current.interimSource.isEmpty || current.committedSource.count < maxSentencesPerSection {
                return (id, nil)
            }
            sealed = endTurn(speaker)
        }
        if let previous = sections.last, previous.speaker != speaker,
           previous.contentState == .open, previous.interimSource.isEmpty {
            sealed = endTurn(previous.speaker)
        }
        let id = nextId
        nextId += 1
        var section = Section(id: id, speaker: speaker)
        section.priorContext = contextSnapshot(for: speaker)
        sections.append(section)
        openSections[speaker] = id
        return (id, sealed)
    }

    /// Stop accepting ASR for this speaker, preserving the last visible hypothesis
    /// if finalization could not commit it. Translation remains independent.
    @discardableResult
    func endTurn(_ speaker: Speaker) -> Int? {
        guard let id = openSections.removeValue(forKey: speaker) else { return nil }
        mutate(id: id) { section in
            section.contentState = .sealed
            let tail = section.interimSource.trimmed
            if !tail.isEmpty { section.committedSource.append(tail) }
            section.interimSource = ""
        }
        if let index = indexOf(id: id), sections[index].sourceText.isEmpty {
            sections.remove(at: index)
        }
        return id
    }

    @discardableResult
    func appendCommitted(_ sentence: String, speaker: Speaker) -> (sectionId: Int, sealed: Int?) {
        let (id, previousSealed) = sectionForUtterance(speaker)
        let text = sentence.trimmed
        if !text.isEmpty {
            mutate(id: id) { section in
                section.committedSource.append(text)
                section.interimSource = ""
            }
            recentSentences[speaker, default: []].append(text)
            let overflow = recentSentences[speaker]!.count - contextWindowSentences
            if overflow > 0 { recentSentences[speaker]!.removeFirst(overflow) }
        }
        // A late final corrects its original bubble once. The speaker's continuation
        // starts a new section after the interruption, never extending an older turn.
        let sealed = sections.last?.id == id ? previousSealed : endTurn(speaker)
        return (id, sealed)
    }

    @discardableResult
    func updateInterim(_ text: String, speaker: Speaker) -> (sectionId: Int?, sealed: Int?) {
        let text = text.trimmed
        guard !text.isEmpty else { return (nil, nil) }
        let (id, sealed) = sectionForUtterance(speaker)
        mutate(id: id) { $0.interimSource = text }
        return (id, sealed)
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
        nextId = 0
        recentSentences.removeAll()
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
        recentSentences.removeAll()
        openSections.removeAll()
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
            if !src.isEmpty {
                recentSentences[r.speaker, default: []].append(src)
                if recentSentences[r.speaker, default: []].count > contextWindowSentences {
                    recentSentences[r.speaker]?.removeFirst()
                }
            }
            maxId = max(maxId, r.id)
        }
        nextId = maxId + 1
    }
}
