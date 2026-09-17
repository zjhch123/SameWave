import Foundation
import Observation

@MainActor
@Observable
final class CaptionStore {
    private(set) var sections: [Section] = []
    private(set) var paragraphLayout = CaptionParagraphLayout()

    private var nextId = 0
    private var openSections: [Speaker: Int] = [:]
    private var hypotheses: [Speaker: SpeechHypothesis] = [:]
    /// Recognition activity, not callback arrival alone: corrections do not extend
    /// it. A one-second gap in added words distinguishes a return from dense overlap.
    private let turnInactivity: Duration = .seconds(1)
    private var lastGrowth: [Speaker: ContinuousClock.Instant] = [:]
    private struct Boundary {
        let prefix: String
        let deadline: ContinuousClock.Instant
    }
    private var boundaries: [Int: Boundary] = [:]
    private let boundaryStability: Duration = .milliseconds(700)

    var nextDraftCommitDeadline: ContinuousClock.Instant? {
        openSections.values.compactMap { id -> ContinuousClock.Instant? in
            guard let boundary = boundaries[id], let section = section(id: id),
                  boundary.prefix == section.sourceText || sections.last?.id == id else { return nil }
            return boundary.deadline
        }.min()
    }

    @discardableResult
    func commitReadyDrafts(at time: ContinuousClock.Instant = .now) -> [Int] {
        confirmBoundaries(at: time, finalSpeaker: nil)
    }

    // MARK: - Lookup

    func section(id: Int) -> Section? { sections.first { $0.id == id } }
    private func indexOf(id: Int) -> Int? { sections.firstIndex { $0.id == id } }
    private func mutate(id: Int, _ body: (inout Section) -> Void) {
        guard let i = indexOf(id: id) else { return }
        body(&sections[i])
    }
    var hasContent: Bool { !sections.isEmpty }

    // MARK: - Source sections

    private func isGrowing(_ speaker: Speaker, at time: ContinuousClock.Instant) -> Bool {
        guard let last = lastGrowth[speaker] else { return false }
        return last.duration(to: time) < turnInactivity
    }

    private func takeTurn(_ speaker: Speaker, at time: ContinuousClock.Instant,
                          startsCaption: Bool) -> (opened: Int, sealed: [Int]) {
        if let id = openSections[speaker], let current = section(id: id),
           current.contentState == .open, !startsCaption,
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
        sections.append(Section(id: id, speaker: speaker))
        openSections[speaker] = id
        return (id, Array(sealed.values))
    }

    private func startsCaption(after words: ArraySlice<SpeechHypothesis.Word>, speaker: Speaker,
                               isFinal: Bool, at time: ContinuousClock.Instant) -> Bool {
        guard let id = words.last?.sectionID ?? openSections[speaker],
              let current = section(id: id) else { return false }
        let interim = words.filter { $0.sectionID == id }.map(\.text).joined()
        let text = TranscriptText.join(current.committedSource + [interim])
        let owned = SpeechHypothesis().revising(text)
        guard let last = owned.last else { return false }
        let chinese = TranscriptText.containsChinese(text)
        if let boundary = boundaries[id], boundary.prefix == text, boundary.deadline <= time { return true }
        return (sections.last?.id != id && (owned.count >= 48 || text.count >= (chinese ? 96 : 240)))
            || (isFinal && (last.endsSentence || (last.endsClause && text.count >= (chinese ? 32 : 96))))
    }

    private func refreshBoundary(id: Int, at time: ContinuousClock.Instant) {
        guard let section = section(id: id), section.contentState == .open else {
            boundaries.removeValue(forKey: id)
            return
        }
        let words = SpeechHypothesis().revising(section.sourceText)
        let chinese = TranscriptText.containsChinese(section.sourceText)
        let overLimit = words.count > 48 || section.sourceText.count > (chinese ? 96 : 240)
        var prefix = ""
        for (index, word) in words.enumerated() {
            prefix += word.text
            let text = prefix.trimmed
            let hasTail = index < words.count - 1
            let hardBoundary = hasTail && (index + 1 >= 48 || text.count >= (chinese ? 96 : 240))
            if word.endsSentence || (word.endsClause && hasTail && text.count >= (chinese ? 32 : 96))
                || hardBoundary {
                let deadline = time.advanced(by: overLimit ? .zero : boundaryStability)
                if boundaries[id]?.prefix != text {
                    boundaries[id] = Boundary(prefix: text, deadline: deadline)
                } else if let previous = boundaries[id], deadline < previous.deadline {
                    boundaries[id] = Boundary(prefix: text, deadline: deadline)
                }
                return
            }
        }
        boundaries.removeValue(forKey: id)
    }

    private func confirmBoundaries(at time: ContinuousClock.Instant, finalSpeaker: Speaker?) -> [Int] {
        var changed: Set<Int> = []
        for speaker in [Speaker.remote, .mine] {
            while let id = openSections[speaker], let boundary = boundaries[id],
                  boundary.deadline <= time || finalSpeaker == speaker,
                  let current = section(id: id) {
                if boundary.prefix == current.sourceText {
                    mutate(id: id) { $0.contentState = .sealed }
                    openSections.removeValue(forKey: speaker)
                    boundaries.removeValue(forKey: id)
                    changed.insert(id)
                    break
                }
                guard sections.last?.id == id else { break }
                let tailID = splitDraft(current, after: boundary.prefix)
                changed.formUnion([id, tailID])
                boundaries.removeValue(forKey: id)
                refreshBoundary(id: tailID, at: time)
            }
        }
        paragraphLayout.update(sections: sections)
        return changed.sorted()
    }

    private func splitDraft(_ current: Section, after prefix: String) -> Int {
        let id = nextId
        nextId += 1
        let committed = TranscriptText.join(current.committedSource)
        var head = current
        var tail = Section(id: id, speaker: current.speaker)
        tail.startedAt = current.startedAt
        if prefix.count <= committed.count {
            head.committedSource = [prefix]
            head.interimSource = ""
            let remainder = String(committed.dropFirst(prefix.count)).trimmed
            tail.committedSource = remainder.isEmpty ? [] : [remainder]
            tail.interimSource = current.interimSource
        } else {
            head.interimSource = String(prefix.dropFirst(committed.count)).trimmed
            tail.interimSource = String(current.sourceText.dropFirst(prefix.count)).trimmed
        }
        head.contentState = .sealed
        head.targetText = ""
        head.requestedSource = ""
        head.translatedGeneration = head.generation
        head.translationState = .pending
        let retainedWords = SpeechHypothesis().revising(head.interimSource).count
        if var hypothesis = hypotheses[current.speaker] {
            let owned = hypothesis.words.indices.filter { hypothesis.words[$0].sectionID == current.id }
            for index in owned.dropFirst(retainedWords) { hypothesis.words[index].sectionID = id }
            hypotheses[current.speaker] = hypothesis
        }
        mutate(id: current.id) { $0 = head }
        sections.append(tail)
        openSections[current.speaker] = id
        return id
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
        for index in words.indices where words[index].sectionID == nil {
            let turn = takeTurn(speaker, at: time,
                                startsCaption: startsCaption(after: words[..<index], speaker: speaker,
                                                             isFinal: isFinal, at: time))
            changed.formUnion(turn.sealed)
            lastGrowth[speaker] = time
            words[index].sectionID = turn.opened
            let partial = words[...index].filter { $0.sectionID == turn.opened }.map(\.text).joined().trimmed
            mutate(id: turn.opened) { $0.interimSource = partial }
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
        // A recognizer can retract an entire fragment. Remove its display row and
        // identity so a late translation cannot bring the deleted words back.
        sections.removeAll { changed.contains($0.id) && $0.sourceText.isEmpty }
        openSections = openSections.filter { section(id: $0.value)?.contentState == .open }
        for id in changed { refreshBoundary(id: id, at: time) }
        changed.formUnion(confirmBoundaries(at: time, finalSpeaker: isFinal ? speaker : nil))
        if isFinal, let id = openSections[speaker],
           let source = section(id: id)?.sourceText,
           SpeechHypothesis().revising(source).last?.endsSentence == true {
            mutate(id: id) { $0.contentState = .sealed }
            openSections.removeValue(forKey: speaker)
            boundaries.removeValue(forKey: id)
        }
        paragraphLayout.update(sections: sections)
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
            boundaries.removeValue(forKey: id)
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

    @discardableResult
    func failTranslation(id: Int, generation: Int) -> Bool {
        guard let index = indexOf(id: id), generation == sections[index].generation,
              generation > sections[index].translatedGeneration else { return false }
        sections[index].translationState = .failed
        return true
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
        paragraphLayout = CaptionParagraphLayout()
        openSections.removeAll()
        hypotheses.removeAll()
        lastGrowth.removeAll()
        boundaries.removeAll()
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
        paragraphLayout = CaptionParagraphLayout()
        openSections.removeAll()
        hypotheses.removeAll()
        lastGrowth.removeAll()
        boundaries.removeAll()
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
        paragraphLayout.update(sections: sections)
    }
}
