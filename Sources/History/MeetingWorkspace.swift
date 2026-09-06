import Foundation
import SwiftData

/// Attachments are managed UTF-8 text copies, independent of the original file URL.
@Model
final class MeetingDocument {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var content: String
    var importedAt: Date
    var record: MeetingRecord?

    init(fileName: String, content: String) {
        id = UUID()
        self.fileName = fileName
        self.content = content
        importedAt = Date()
    }

    var source: VocabularySourceDocument {
        VocabularySourceDocument(fileName: fileName, content: content)
    }
}

@Model
final class MeetingVocabularyTerm {
    @Attribute(.unique) var id: UUID
    var phrase: String
    var record: MeetingRecord?

    init(phrase: String) {
        id = UUID()
        self.phrase = phrase
    }
}

enum InsightScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case cumulative
    case latestExchange
    var id: String { rawValue }
    var label: String { self == .cumulative ? "Meeting so far" : "Latest exchange" }
}

@Model
final class InsightDefinition {
    @Attribute(.unique) var id: UUID
    var title: String
    var prompt: String
    var automaticallyUpdates: Bool
    var scope: String
    var createdAt: Date
    var record: MeetingRecord?

    init(title: String, prompt: String, automaticallyUpdates: Bool = false,
         scope: InsightScope = .cumulative) {
        id = UUID()
        self.title = title
        self.prompt = prompt
        self.automaticallyUpdates = automaticallyUpdates
        self.scope = scope.rawValue
        createdAt = Date()
    }

    var configuration: InsightConfiguration {
        InsightConfiguration(id: id, title: title, prompt: prompt,
                             scope: InsightScope(rawValue: scope)!)
    }
}

struct InsightConfiguration: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var prompt: String
    var scope: InsightScope

    static let summary = InsightConfiguration(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Meeting Insights",
        prompt: "Summarize the complete meeting: final decisions, agreed actions and owners, stated dates, unresolved questions, and remaining disagreements. Reflect later changes and retractions. Leave missing owners and dates unknown.",
        scope: .cumulative
    )
}

extension MeetingRecord {
    var orderedDocuments: [MeetingDocument] {
        documents.sorted {
            $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt < $1.importedAt
        }
    }

    var confirmedVocabulary: [String] {
        vocabulary.sorted { $0.phrase.localizedStandardCompare($1.phrase) == .orderedAscending }
            .map(\.phrase)
    }

    func effectiveVocabulary(global: [String]) -> [String] {
        SpeechVocabularySettings.normalized(confirmedVocabulary + global)
    }

    var orderedDefinitions: [InsightDefinition] {
        definitions.sorted { $0.createdAt < $1.createdAt }
    }
}

extension MeetingHistoryStore {
    func createDraft(languagePair: MeetingLanguagePair, now: Date = .now) throws -> MeetingRecord {
        let record = MeetingRecord(startedAt: now, endedAt: now, languagePair: languagePair,
                                   lineCount: 0, status: .draft)
        record.createdAt = now
        context.insert(record)
        let overview = InsightDefinition(
            title: "Meeting Overview",
            prompt: "Give a broad, structured meeting overview with key topics, suggestions, action items, decisions, and open questions. Return the summary parts, not a flat list of points. Track commitments and any later changes.",
            automaticallyUpdates: false
        )
        overview.record = record
        context.insert(overview)
        try save()
        return record
    }

    func attach(_ documents: [VocabularySourceDocument], to record: MeetingRecord) throws {
        let existing = record.orderedDocuments.map(\.source)
        let merged = try VocabularyDocumentLoader.merging(documents, into: existing)
        for document in merged.dropFirst(existing.count) {
            let attachment = MeetingDocument(fileName: document.fileName, content: document.content)
            attachment.record = record
            context.insert(attachment)
        }
        try save()
    }

    func removeAttachment(_ document: MeetingDocument) throws {
        document.record?.documents.removeAll { $0.id == document.id }
        context.delete(document)
        try save()
    }

    /// Restore only this operation on failure, preserving unrelated model edits.
    func replaceVocabulary(_ phrases: [String], in record: MeetingRecord,
                           persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let normalized = SpeechVocabularySettings.normalized(phrases)
        let original = record.vocabulary
        let removed = original.filter { !normalized.contains($0.phrase) }
        let inserted = normalized.filter { phrase in !original.contains { $0.phrase == phrase } }
            .map { MeetingVocabularyTerm(phrase: $0) }
        guard !removed.isEmpty || !inserted.isEmpty else { return }
        // Flush earlier edit bookkeeping before SwiftData groups this operation.
        // Reinserting deleted models by hand leaves stale deletion state on retry.
        context.processPendingChanges()
        let previousUndoManager = context.undoManager
        let undoManager = UndoManager()
        context.undoManager = undoManager
        defer { context.undoManager = previousUndoManager }
        for term in removed { context.delete(term) }
        for term in inserted { context.insert(term); term.record = record }
        record.vocabulary = original.filter { normalized.contains($0.phrase) } + inserted
        context.processPendingChanges()
        do { try persist(context) }
        catch {
            undoManager.undo()
            context.processPendingChanges()
            throw error
        }
    }
}
