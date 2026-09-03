import Foundation
import SwiftData

/// A persisted meeting session. Stored via SwiftData (native, on-device, backed by
/// SQLite in Application Support — no third-party dependency, ASCII path). Its lines
/// carry per-utterance spoken-time stamps.
///
/// A record is written INCREMENTALLY, not once at stop: `status` tracks its
/// lifecycle ("recording" → "paused" → "ended"), and the coordinator autosaves the
/// live transcript every few seconds. So a meeting survives a pause, an app quit, or
/// a crash — on next launch any non-"ended" record is recovered as a paused session
/// the user can resume (losing at most the last few unsynced seconds).
@Model
final class MeetingRecord {
    /// Stable id (also used to select in the UI).
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    /// Persisted raw value of `MeetingLanguagePair`.
    var language: String
    /// Cached count so the list doesn't have to fault every line just to show it.
    var lineCount: Int
    /// Persisted raw value of `MeetingStatus`.
    var status: String

    /// Cached AI insight for this meeting, encoded as `InsightResult` JSON.
    var insightJSON: String?

    /// When the transcript was last LLM-refined (source cleaned + translation redone),
    /// or nil if never. Drives the "优化译文/重新优化" button label and whether the
    /// 原始/优化 toggle appears. The refined text itself lives per-line (additive, never
    /// overwriting the originals) — see `TranscriptLine.refinedSource/refinedTarget`.
    var refinedAt: Date?
    /// Cached glossary (term → suggested Chinese / keep-original) from the last refine,
    /// as JSON. Fed back into the next refine so terminology stays consistent.
    var glossaryJSON: String?

    /// The transcript lines, ordered by `orderIndex`. Deleting the record deletes them.
    @Relationship(deleteRule: .cascade, inverse: \TranscriptLine.record)
    var lines: [TranscriptLine]

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date,
         languagePair: MeetingLanguagePair,
         lineCount: Int, status: MeetingStatus, insightJSON: String? = nil,
         refinedAt: Date? = nil, glossaryJSON: String? = nil,
         lines: [TranscriptLine] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.language = languagePair.rawValue
        self.lineCount = lineCount
        self.status = status.rawValue
        self.insightJSON = insightJSON
        self.refinedAt = refinedAt
        self.glossaryJSON = glossaryJSON
        self.lines = lines
    }

    var durationSec: Int { max(0, Int(endedAt.timeIntervalSince(startedAt))) }

    /// "2026年7月7日 18:27" — the row/header title.
    var displayDate: String { DateFormat.dayTime.string(from: startedAt) }

    var durationText: String {
        let s = durationSec, m = s / 60, r = s % 60
        return m > 0 ? "\(m) 分 \(r) 秒" : "\(r) 秒"
    }

    /// "N 段 · 时长" — the one-line summary shown in the sidebar row and stage header.
    var metaText: String { "\(lineCount) 段 · \(durationText)" }

    /// Whether this meeting's lines should render/export the source text as a secondary
    /// echo under the primary line. The target is primary only when source and target
    /// languages differ. Same-language meetings store the recognized source as the target,
    /// so repeating it would duplicate the caption.
    var showsSourceEcho: Bool { languagePair.needsTranslation }

    /// The decoded cached insight, or nil if none was generated (or it's unreadable).
    var insight: InsightResult? { InsightResult.decode(from: insightJSON) }

    /// Whether this meeting has an LLM-refined version (source cleaned + translation
    /// redone). Gates the 原始/优化 toggle and picks refined text for export.
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
    /// Chinese primary; falls back to source if untranslated.
    var displayText: String {
        let zh = targetText.trimmed
        return zh.isEmpty ? sourceText : zh
    }
    /// "18:27" — the per-line spoken time.
    var timeText: String { DateFormat.clock.string(from: spokenAt) }

    /// Source to display given the 原始/优化 toggle: the refined original when asked and
    /// available, else the raw original. Falling back to the original means a page-wide
    /// "优化" toggle still shows every line (even ones the LLM happened to skip).
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

    init(configuration: ModelConfiguration? = nil) throws {
        if let configuration {
            container = try ModelContainer(
                for: MeetingRecord.self,
                TranscriptLine.self,
                configurations: configuration
            )
        } else {
            container = try ModelContainer(for: MeetingRecord.self, TranscriptLine.self)
        }
    }

    var context: ModelContext { container.mainContext }

    /// Open a new live record (status "recording") the moment a meeting starts, so it
    /// exists on disk before a single word is spoken. Returned so the coordinator can
    /// keep syncing into it.
    func beginRecord(startedAt: Date,
                     languagePair: MeetingLanguagePair) throws -> MeetingRecord {
        let r = MeetingRecord(
            startedAt: startedAt,
            endedAt: startedAt,
            languagePair: languagePair,
            lineCount: 0,
            status: .recording
        )
        context.insert(r)
        try save()
        return r
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

    /// Finalize a meeting: one last sync, then mark "ended" so it enters history. An
    /// empty meeting (nothing was said) is deleted rather than left as a blank row.
    func finish(_ record: MeetingRecord, sections: [Section], endedAt: Date) throws {
        update(record: record, sections: sections, endedAt: endedAt, status: .ended)
        if record.lineCount == 0 {
            context.delete(record)
        }
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

    func delete(_ record: MeetingRecord) throws {
        context.delete(record)
        try save()
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
