import Foundation
import Observation

/// Central observable store the transcript renders from, and the pipeline writes to.
///
/// It owns a **single-floor segmentation state machine**: at most ONE section is
/// open ("holds the floor") at any instant. Whoever produces a finalized sentence
/// takes the floor; taking it from someone else SEALS that speaker's section (spec
/// Rule A — a speaker switch seals the current section and opens a new one). Because
/// only one section is ever open, the section list is strictly chronological by the
/// moment each turn began — a still-open section can never linger absorbing later
/// content at an early position, which is what previously let a "mine" bubble float
/// above a later "remote" one.
///
/// This deliberately collapses the spec's transient OVERLAP state: a single-column
/// transcript can't render two people truly at once, so we serialize by
/// finalized-sentence order, which is exactly "render whoever spoke, when they
/// spoke." A speaker resuming after being cut off simply takes the floor again and
/// gets a fresh section placed at its true chronological position (spec §4.3 order
/// is preserved: the interrupter's sentence, committed first, sits before the
/// resumer's, committed later).
///
/// Threading: ASR callbacks and the translation task both hop to the main actor
/// before mutating this, so the SwiftUI transcript updates safely.
@MainActor
@Observable
final class CaptionStore {
    private(set) var sections: [Section] = []

    /// DISPLAY cap: a single-speaker section seals and opens a fresh one once it has
    /// accumulated `maxSentencesPerSection` sentences of source, checked at the next
    /// commit (isFinal). Governs bubble size ONLY; translation context is the separate
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

    // MARK: - Floor state (single open section)

    private var nextId = 0
    /// The speaker currently holding the floor (has the one open section), or nil.
    private var floorSpeaker: Speaker?
    /// The id of that one open section.
    private var floorSectionId: Int?

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

    // MARK: - Rule A: single-floor segmentation

    /// Give `speaker` the floor, sealing whoever held it before (a speaker switch).
    /// Idempotent if `speaker` already holds it. Returns the newly-open section id
    /// and any section this SEALED (so its final translation can be scheduled).
    @discardableResult
    private func takeFloor(_ speaker: Speaker) -> (opened: Int, sealed: Int?) {
        if floorSpeaker == speaker, let id = floorSectionId { return (id, nil) }

        var sealed: Int? = nil
        if let held = floorSectionId {
            seal(id: held)
            sealed = held
        }
        let id = nextId; nextId += 1
        var s = Section(id: id, speaker: speaker)   // contentState defaults to .open
        s.priorContext = contextSnapshot(for: speaker)   // freeze the speaker's leading context
        appendSection(s)
        floorSpeaker = speaker
        floorSectionId = id
        return (id, sealed)
    }

    /// Genuine end of `speaker`'s turn (a silence gap, or stop). Seals their open
    /// section and clears the floor so the next content starts a fresh section.
    @discardableResult
    func endTurn(_ speaker: Speaker) -> Int? {
        guard floorSpeaker == speaker, let id = floorSectionId else { return nil }
        seal(id: id)
        floorSpeaker = nil
        floorSectionId = nil
        return id
    }

    /// OPEN → SEALED: stop accepting new source; translation continues independently
    /// (Rule B). If the turn is sealed while a live hypothesis is still showing (the
    /// sentence never got a final commit — common for long utterances), that interim
    /// is PROMOTED into committed source so the visible text can never blink out. A
    /// section with genuinely nothing (no committed AND no interim — a spurious onset
    /// from transient echo) is pruned.
    private func seal(id: Int) {
        mutate(id: id) { s in
            s.contentState = .sealed
            let tail = s.interimSource.trimmed
            if s.committedSource.isEmpty && !tail.isEmpty {
                s.committedSource = [tail]     // keep what the user is already seeing
            }
            s.interimSource = ""
        }
        // Prune a section that ended up with genuinely nothing (a spurious onset from
        // transient echo): no committed source even after interim promotion.
        if let i = indexOf(id: id), sections[i].committedSource.isEmpty {
            sections.remove(at: i)
        }
    }

    // MARK: - Source text (ASR in)

    /// A finalized sentence from `speaker`. Takes the floor (sealing the other
    /// speaker if they held it), appends, and returns (its section id, any sealed id).
    /// A same-speaker monologue is kept as ONE display section until it fills
    /// `maxSentencesPerSection` sentences, then this commit seals it and opens a fresh
    /// one. The fresh section does NOT lose translation context: its `priorContext` was
    /// frozen from `recentSentences` at open, so the sliding context window is
    /// sentence-scoped and survives the split.
    @discardableResult
    func appendCommitted(_ sentence: String, speaker: Speaker) -> (sectionId: Int, sealed: Int?) {
        let text = sentence.trimmed
        var (id, sealed) = takeFloor(speaker)
        // Same-speaker section full (by sentence count) → seal it and open the next one;
        // this committed sentence lands in the fresh section.
        if let sec = section(id: id),
           sec.committedSource.count >= maxSentencesPerSection {
            endTurn(speaker)
            sealed = id
            (id, _) = takeFloor(speaker)
        }
        if !text.isEmpty {
            mutate(id: id) { s in
                s.committedSource.append(text)
                s.interimSource = ""
            }
            // Feed the rolling context buffer AFTER appending, so this sentence is
            // context for the NEXT section, never for its own.
            recentSentences[speaker, default: []].append(text)
            let overflow = recentSentences[speaker]!.count - contextWindowSentences
            if overflow > 0 { recentSentences[speaker]!.removeFirst(overflow) }
        }
        return (id, sealed)
    }

    /// A volatile hypothesis from `speaker`. If they already hold the floor (or the
    /// floor is idle), it grabs/updates their section's live tail; if the OTHER
    /// speaker holds the floor, the interim is IGNORED — only a finalized sentence is
    /// allowed to seize the floor, which prevents transient/echo partials from one
    /// stream thrashing the other's open turn. Returns the touched section id (nil if
    /// ignored) and any sealed id.
    @discardableResult
    func updateInterim(_ text: String, speaker: Speaker) -> (sectionId: Int?, sealed: Int?) {
        let t = text.trimmed
        // Non-floor interim while someone else is mid-turn: ignore (no seize).
        if let holder = floorSpeaker, holder != speaker {
            return (nil, nil)
        }
        let (id, sealed) = takeFloor(speaker)   // grabs the idle floor, or is a no-op
        mutate(id: id) { $0.interimSource = t }
        return (id, sealed)
    }

    // MARK: - Translation (Rule B — independent axis)

    @discardableResult
    func beginTranslation(id: Int) -> Int {
        var g = 0
        mutate(id: id) { s in
            s.generation += 1
            g = s.generation
            if s.translationState != .done { s.translationState = .translating }
        }
        return g
    }

    /// Apply a translation result if not stale. `final` (the sealed-section pass)
    /// drives DONE.
    func applyTranslation(_ chinese: String, id: Int, generation: Int, final: Bool) {
        mutate(id: id) { s in
            guard generation == s.generation else { return }
            let zh = chinese.trimmed
            if !zh.isEmpty { s.targetText = zh }
            if final && s.contentState == .sealed {
                s.translationState = .done
            } else if s.translationState == .pending {
                s.translationState = .translating
            }
        }
    }

    func failTranslation(id: Int, generation: Int) {
        mutate(id: id) { section in
            guard generation == section.generation else { return }
            section.translationState = .failed
        }
    }

    /// Chinese-meeting mode: the recognized text IS the caption.
    func setNativeCaption(id: Int) {
        mutate(id: id) { s in
            s.targetText = s.sourceText
            s.translationState = .done
        }
    }

    // MARK: - Helpers

    private func appendSection(_ s: Section) {
        sections.append(s)
    }

    func clear() {
        sections.removeAll()
        floorSpeaker = nil
        floorSectionId = nil
        nextId = 0
        recentSentences.removeAll()
    }

    /// Rebuild the transcript from a persisted meeting so a resumed / recovered
    /// session shows its earlier content and can keep recording into it. Every
    /// restored section comes back SEALED (its turn is over) and DONE (already
    /// translated); the floor is left idle so the next spoken word opens a fresh
    /// section. Crucially each section keeps its ORIGINAL `sectionId`, and `nextId`
    /// resumes past the max — so continued incremental autosaves upsert the same rows
    /// instead of duplicating them, and new sections never collide with old ids.
    func restore(sections restored: [(id: Int, speaker: Speaker, source: String,
                                      target: String, startedAt: Date)]) {
        sections.removeAll()
        recentSentences.removeAll()
        floorSpeaker = nil
        floorSectionId = nil
        var maxId = -1
        for r in restored {
            var s = Section(id: r.id, speaker: r.speaker)
            s.contentState = .sealed
            s.translationState = .done
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
