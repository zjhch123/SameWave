import Foundation
import SwiftData

/// A persisted meeting session. Stored via SwiftData (native, on-device, backed by
/// SQLite in Application Support — no third-party dependency, ASCII path). Its lines
/// carry per-utterance spoken-time stamps.
///
/// A record is written INCREMENTALLY, not once at stop: `status` tracks its
/// lifecycle ("draft" → "recording" → "paused" → "ended"). Preparation saves before
/// capture, and the coordinator autosaves the live transcript every few seconds.
/// Interrupted recordings recover paused; prepared drafts remain drafts.
@Model
final class MeetingRecord {
    /// Stable id (also used to select in the UI).
    @Attribute(.unique) var id: UUID
    var createdAt: Date = Date()
    var userTitle: String = ""
    var startedAt: Date
    var endedAt: Date
    /// Persisted raw value of `MeetingLanguagePair`.
    var language: String
    /// Cached count so the list doesn't have to fault every line just to show it.
    var lineCount: Int
    /// Persisted raw value of `MeetingStatus`.
    var status: String

    /// Concise title generated from the transcript by the configured AI provider.
    /// Used when no user title is saved; a missing title displays the start date.
    var aiTitle: String?

    /// When the transcript was last LLM-refined (source cleaned + translation redone),
    /// or nil if never. Drives the "Refine Translation/Refine Again" button label and whether the
    /// Original/Refined toggle appears. The refined text itself lives per-line (additive, never
    /// overwriting the originals) — see `TranscriptLine.refinedSource/refinedTarget`.
    var refinedAt: Date?
    /// Cached glossary (term → suggested Chinese / keep-original) from the last refine,
    /// as JSON. Fed back into the next refine so terminology stays consistent.
    var glossaryJSON: String?

    /// The transcript lines, ordered by `orderIndex`. Deleting the record deletes them.
    @Relationship(deleteRule: .cascade, inverse: \TranscriptLine.record)
    var lines: [TranscriptLine]
    @Relationship(deleteRule: .cascade, inverse: \MeetingDocument.record)
    var documents: [MeetingDocument] = []
    @Relationship(deleteRule: .cascade, inverse: \MeetingVocabularyTerm.record)
    var vocabulary: [MeetingVocabularyTerm] = []
    @Relationship(deleteRule: .cascade, inverse: \InsightDefinition.record)
    var definitions: [InsightDefinition] = []
    @Relationship(deleteRule: .cascade, inverse: \InsightSnapshot.record)
    var insightSnapshots: [InsightSnapshot] = []

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date,
         languagePair: MeetingLanguagePair,
         lineCount: Int, status: MeetingStatus,
         aiTitle: String? = nil,
         refinedAt: Date? = nil, glossaryJSON: String? = nil,
         lines: [TranscriptLine] = []) {
        self.id = id
        self.createdAt = startedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.language = languagePair.rawValue
        self.lineCount = lineCount
        self.status = status.rawValue
        self.aiTitle = aiTitle
        self.refinedAt = refinedAt
        self.glossaryJSON = glossaryJSON
        self.lines = lines
    }

    var durationSec: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }

    var displayDate: String { startedAt.formatted(date: .abbreviated, time: .shortened) }

    var hasAITitle: Bool { aiTitle?.trimmed.isEmpty == false }
    var hasTitle: Bool { !userTitle.trimmed.isEmpty || hasAITitle }
    var needsAITitle: Bool { !hasTitle }

    var displayTitle: String {
        if !userTitle.trimmed.isEmpty { return userTitle.trimmed }
        guard let title = aiTitle?.trimmed, !title.isEmpty else { return displayDate }
        return title
    }

    var durationText: String {
        let s = durationSec, m = s / 60, r = s % 60
        return m > 0 ? "\(m)m \(r)s" : "\(r)s"
    }

    /// "N sections · duration" — the one-line summary shown in the sidebar row and stage header.
    var metaText: String {
        let minutes = durationSec / 60, seconds = durationSec % 60
        let duration = minutes > 0
            ? String(localized: "\(minutes)m \(seconds)s")
            : String(localized: "\(seconds)s")
        return String(localized: "\(lineCount) sections · \(duration)")
    }

    /// Keep the original date visible as secondary metadata after a title replaces it.
    var displayMetaText: String {
        guard hasTitle else { return metaText }
        return "\(displayDate) · \(metaText)"
    }

    /// Whether this meeting's lines should render/export the source text as a secondary
    /// echo under the primary line. The target is primary only when source and target
    /// languages differ. Same-language meetings store the recognized source as the target,
    /// so repeating it would duplicate the caption.
    var showsSourceEcho: Bool { languagePair.needsTranslation }

    /// Whether this meeting has an LLM-refined version (source cleaned + translation
    /// redone). Gates the Original/Refined toggle and picks refined text for export.
    var hasRefinement: Bool { refinedAt != nil }

    /// The persisted source/target pair used by recognition, translation, refinement,
    /// display, and export.
    var languagePair: MeetingLanguagePair {
        guard let value = MeetingLanguagePair(rawValue: language) else {
            preconditionFailure("Invalid persisted meeting language pair: \(language)")
        }
        return value
    }

    var meetingStatus: MeetingStatus {
        guard let value = MeetingStatus(rawValue: status) else {
            preconditionFailure("Invalid persisted meeting status: \(status)")
        }
        return value
    }
}

/// One transcript line (== one Section at save time): who spoke, the source text,
/// its target-language translation, and WHEN it was spoken. `sectionId` ties the line back
/// to its live Section so incremental autosaves can UPSERT (update-in-place) rather
/// than wipe-and-rewrite every few seconds.
@Model
final class TranscriptLine {
    /// "me" or "remote".
    var speaker: String
    var sourceText: String
    var targetText: String
    /// Wall-clock time this line was spoken (the section's start).
    var spokenAt: Date
    /// Ordering within the meeting (== section id order == chronological).
    var orderIndex: Int
    /// The live Section id this line came from — the upsert key for incremental
    /// autosave.
    var sectionId: Int

    /// LLM-refined variants, ADDITIVE — the originals (`sourceText`/`targetText`) are
    /// never overwritten, so the user can always switch back and verify what was actually
    /// said. nil until this line has been refined. `refinedSource` = conservatively
    /// cleaned original (filler words removed, no rewriting); `refinedTarget` = translation
    /// redone with full context + glossary.
    var refinedSource: String?
    var refinedTarget: String?

    var record: MeetingRecord?

    init(speaker: Speaker, sourceText: String, targetText: String, spokenAt: Date,
         orderIndex: Int, sectionId: Int,
         refinedSource: String? = nil, refinedTarget: String? = nil) {
        self.speaker = speaker.persistedValue
        self.sourceText = sourceText
        self.targetText = targetText
        self.spokenAt = spokenAt
        self.orderIndex = orderIndex
        self.sectionId = sectionId
        self.refinedSource = refinedSource
        self.refinedTarget = refinedTarget
    }

    var isMine: Bool { speaker == Speaker.mine.persistedValue }
    /// "18:27" — the per-line spoken time.
    var timeText: String { DateFormat.clock.string(from: spokenAt) }

    /// Source to display given the Original/Refined toggle: the refined original when asked and
    /// available, else the raw original. Falling back to the original means a page-wide
    /// "Refined" toggle still shows every line (even ones the LLM happened to skip).
    func displaySource(refined: Bool) -> String {
        if refined, let r = refinedSource?.trimmed, !r.isEmpty { return r }
        return sourceText
    }
    /// Translation to display given the toggle, same fallback rule as `displaySource`.
    func displayTarget(refined: Bool) -> String {
        if refined, let r = refinedTarget?.trimmed, !r.isEmpty { return r }
        return targetText
    }
}

/// Owns the shared SwiftData container and provides incremental save/recover/delete.
/// A single container is created at launch and shared by the coordinator (writes) and
/// the sidebar (`@Query` reads).
@MainActor
final class MeetingHistoryStore {
    let container: ModelContainer

    static func persistentConfiguration(
        applicationSupportDirectory: URL = .applicationSupportDirectory
    ) throws -> ModelConfiguration {
        let directory = applicationSupportDirectory.appending(path: "SameWave", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ModelConfiguration(url: directory.appending(path: "MeetingHistory.store"))
    }

    init(configuration: ModelConfiguration) throws {
        let schema = Schema([MeetingRecord.self, TranscriptLine.self, MeetingDocument.self,
                             MeetingVocabularyTerm.self, InsightDefinition.self, InsightSnapshot.self])
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    var context: ModelContext { container.mainContext }

    func beginCapture(_ record: MeetingRecord, languagePair: MeetingLanguagePair,
                      now: Date = .now) throws {
        record.language = languagePair.rawValue
        record.startedAt = now
        record.endedAt = now
        record.status = MeetingStatus.recording.rawValue
        try save()
    }

    /// Incrementally sync the live transcript into `record`: UPSERT each meaningful
    /// section by its `sectionId` (update in place, or insert), drop lines whose
    /// section was pruned, and refresh count + endedAt. Cheap enough to call every few
    /// seconds and on every state change.
    func sync(record: MeetingRecord, sections: [Section], endedAt: Date,
              status: MeetingStatus? = nil) throws {
        update(record: record, sections: sections, endedAt: endedAt, status: status)
        try save()
    }

    private func update(record: MeetingRecord, sections: [Section], endedAt: Date,
                        status: MeetingStatus?) {
        let meaningful = sections.filter { $0.sourceText.hasSpokenContent || $0.targetText.hasSpokenContent }
        var existing: [Int: TranscriptLine] = [:]
        for l in record.lines { existing[l.sectionId] = l }

        var keptIds = Set<Int>()
        for (i, s) in meaningful.enumerated() {
            keptIds.insert(s.id)
            let who = s.speaker
            if let line = existing[s.id] {
                line.speaker = who.persistedValue
                line.sourceText = s.sourceText
                line.targetText = s.targetText
                line.spokenAt = s.startedAt
                line.orderIndex = i
            } else {
                let line = TranscriptLine(speaker: who, sourceText: s.sourceText,
                                          targetText: s.targetText, spokenAt: s.startedAt,
                                          orderIndex: i, sectionId: s.id)
                line.record = record
                context.insert(line)
            }
        }
        // A section can be pruned (empty onset from echo) after a line existed for it.
        let stale = record.lines.filter { !keptIds.contains($0.sectionId) }
        for l in stale { context.delete(l) }

        record.lineCount = meaningful.count
        record.endedAt = endedAt
        if let status { record.status = status.rawValue }
    }

    /// Mark a record's lifecycle status (e.g. "paused" on pause, "recording" on resume).
    func setStatus(_ record: MeetingRecord, _ status: MeetingStatus) throws {
        record.status = status.rawValue
        try save()
    }

    /// Finalize without deleting preparation or an empty workspace.
    func finish(_ record: MeetingRecord, sections: [Section], endedAt: Date) throws {
        update(record: record, sections: sections, endedAt: endedAt, status: .ended)
        try save()
    }

    /// All records that never reached "ended" (interrupted by quit/crash/pause),
    /// newest first — candidates for recovery on launch.
    func unfinishedRecords() throws -> [MeetingRecord] {
        let ended = MeetingStatus.ended.rawValue
        let d = FetchDescriptor<MeetingRecord>(
            predicate: #Predicate { $0.status != ended },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try context.fetch(d)
    }

    func record(id: UUID) throws -> MeetingRecord? {
        var descriptor = FetchDescriptor<MeetingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func mostRecentRecord() throws -> MeetingRecord? {
        var descriptor = FetchDescriptor<MeetingRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func delete(_ record: MeetingRecord) throws {
        context.delete(record)
        try save()
    }

    /// Restore only the affected fields if this write fails; other meeting work is independent.
    func saveRefinement(_ outcome: TranscriptRefiner.Outcome, to record: MeetingRecord,
                        persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let originals = record.lines.map { ($0, $0.refinedSource, $0.refinedTarget) }
        let originalGlossary = record.glossaryJSON
        let originalDate = record.refinedAt
        for line in record.lines {
            guard let refined = outcome.byIndex[line.orderIndex] else { continue }
            let source = refined.source.trimmed
            if !source.isEmpty {
                line.refinedSource = source
                if !record.languagePair.needsTranslation { line.refinedTarget = source }
            }
            if let target = refined.target?.trimmed, !target.isEmpty { line.refinedTarget = target }
        }
        record.glossaryJSON = outcome.glossaryJSON
        record.refinedAt = .now
        do { try persist(context) }
        catch {
            for (line, source, target) in originals {
                line.refinedSource = source
                line.refinedTarget = target
            }
            record.glossaryJSON = originalGlossary
            record.refinedAt = originalDate
            throw error
        }
    }

    func saveGeneratedTitle(_ title: String, to record: MeetingRecord) throws {
        let original = record.aiTitle
        record.aiTitle = title
        do { try context.save() }
        catch { record.aiTitle = original; throw error }
    }

    /// Keeps a failed write from leaking uncommitted model mutations into the next
    /// operation. The coordinator's `CaptionStore` remains the retry source of truth.
    func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
