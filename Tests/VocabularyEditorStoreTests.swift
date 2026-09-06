import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class VocabularyEditorStoreTests: XCTestCase {
    func testManualAddEditRemoveAndEmptyVocabularyPersist() throws {
        let defaults = Phase2Fixture.defaults(self)
        let saved = SpeechVocabularySettings(defaults: defaults)
        saved.save(["XPay"])
        let editor = VocabularyEditorStore(aiSettings: AISettings(defaults: defaults), settings: saved)
        editor.manualText = " xpay \nSwiftData\n\nSwiftData\nACME, Inc."
        editor.addTerms()
        XCTAssertEqual(saved.phrases, ["XPay", "SwiftData", "ACME, Inc."])
        XCTAssertEqual(editor.vocabularyMessage, "Added 2 terms · Skipped 2 duplicates")
        XCTAssertTrue(editor.manualText.isEmpty)
        editor.beginEditing("SwiftData")
        editor.editedText = "Swift Data"
        editor.cancelEditing()
        XCTAssertEqual(saved.phrases[1], "SwiftData")
        editor.beginEditing("SwiftData")
        editor.editedText = "Swift Data"
        editor.saveEdit()
        XCTAssertEqual(saved.phrases[1], "Swift Data")
        editor.beginEditing("XPay")
        editor.editedText = "swift data"
        editor.saveEdit()
        XCTAssertEqual(saved.phrases, ["swift data", "ACME, Inc."])
        for phrase in editor.phrases { editor.remove(phrase) }
        XCTAssertTrue(SpeechVocabularySettings(defaults: defaults).phrases.isEmpty)
    }

    func testInvalidManualLineBlocksWholeAddAndSuggestionsDoNotCommitManualDraft() {
        let defaults = Phase2Fixture.defaults(self)
        let saved = SpeechVocabularySettings(defaults: defaults)
        saved.save([])
        let editor = VocabularyEditorStore(aiSettings: AISettings(defaults: defaults), settings: saved)
        let text = "Valid\n" + String(repeating: "x", count: 101)
        editor.manualText = text
        editor.addTerms()
        XCTAssertEqual(editor.manualText, text)
        XCTAssertTrue(saved.phrases.isEmpty)
        editor.importer.candidates = [
            .init(originalPhrase: "Generated", text: "Generated"),
            .init(originalPhrase: "Unchecked", text: "bad\nline", isSelected: false)
        ]
        XCTAssertFalse(editor.importer.hasInvalidSelection)
        let uncheckedID = editor.importer.candidates[1].id
        editor.importer.saveSelected()
        XCTAssertEqual(saved.phrases, ["Generated"])
        XCTAssertEqual(editor.importer.candidates.map(\.id), [uncheckedID])
        XCTAssertEqual(editor.manualText, text)
        editor.importer.discardSuggestions()
        XCTAssertTrue(editor.importer.candidates.isEmpty)
        XCTAssertEqual(saved.phrases, ["Generated"])
        XCTAssertEqual(editor.manualText, text)
    }

    func testWriteFailureRetainsOriginalsManualRowAndSuggestionDraftsForRetry() {
        let settings = AISettings(defaults: Phase2Fixture.defaults(self))
        var phrases = ["Original"]
        var fail = true
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: settings, readPhrases: { phrases }, replacePhrases: {
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            phrases = $0
        })
        editor.manualText = "New"
        editor.addTerms()
        XCTAssertEqual(phrases, ["Original"])
        XCTAssertEqual(editor.manualText, "New")
        XCTAssertNotNil(editor.vocabularyError)
        editor.beginEditing("Original")
        editor.editedText = "Edited"
        editor.saveEdit()
        XCTAssertEqual(phrases, ["Original"])
        XCTAssertEqual(editor.editedText, "Edited")
        XCTAssertEqual(editor.editingPhrase, "Original")
        editor.remove("Original")
        XCTAssertEqual(phrases, ["Original"])
        editor.importer.candidates = [.init(originalPhrase: "AI Term", text: "AI Term")]
        let id = editor.importer.candidates[0].id
        editor.importer.saveSelected()
        XCTAssertEqual(editor.importer.candidates[0].id, id)
        XCTAssertNotNil(editor.importer.saveError)
        fail = false
        editor.saveEdit()
        editor.addTerms()
        editor.importer.saveSelected()
        XCTAssertEqual(phrases, ["Edited", "New", "AI Term"])
        XCTAssertNil(editor.vocabularyError)
        XCTAssertNil(editor.importer.saveError)
    }

    func testPersonalFilesAreLocalTemporaryDeduplicatedAndAtomicOnFailure() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let editor = VocabularyEditorStore(aiSettings: AISettings(defaults: defaults), settings: SpeechVocabularySettings(defaults: defaults))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { editor.invalidate() }
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let good = directory.appending(path: "good.md")
        try "XPay".write(to: good, atomically: true, encoding: .utf8)
        editor.chooseFiles(.success([good]))
        try await Phase2Fixture.waitUntil { !editor.isLoadingFiles }
        XCTAssertEqual(editor.documents.map(\.content), ["XPay"])
        XCTAssertEqual(editor.importer.state, .idle)
        XCTAssertTrue(editor.importer.requests.isEmpty)
        editor.chooseFiles(.success([good]))
        try await Phase2Fixture.waitUntil { !editor.isLoadingFiles }
        XCTAssertEqual(editor.documents.count, 1)
        editor.chooseFiles(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(editor.fileError)
        let large = directory.appending(path: "large.md")
        try String(repeating: "a", count: 3_000_001).write(to: large, atomically: true, encoding: .utf8)
        editor.chooseFiles(.success([good, large]))
        try await Phase2Fixture.waitUntil { !editor.isLoadingFiles }
        XCTAssertNotNil(editor.fileError)
        XCTAssertEqual(editor.documents.map(\.fileName), ["good.md"])
        editor.removeDocument(at: 0)
        XCTAssertTrue(editor.documents.isEmpty)
        XCTAssertNil(editor.fileError)
        XCTAssertTrue(VocabularyEditorStore(aiSettings: AISettings(defaults: defaults), settings: SpeechVocabularySettings(defaults: defaults)).documents.isEmpty)
    }

    func testFailedMeetingWriteRestoresAffectedRowsWithoutRollingBackOtherEdits() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let other = try history.createDraft(languagePair: .englishToEnglish)
        try history.replaceVocabulary(["XPay", "SwiftData"], in: record)
        let identities = Set(record.vocabulary.map(\.id))
        other.userTitle = "Pending title"
        for _ in 0..<2 {
            XCTAssertThrowsError(try history.replaceVocabulary(["New", "SwiftData"], in: record, persist: { _ in
                throw CocoaError(.fileWriteOutOfSpace)
            }))
            XCTAssertEqual(Set(record.confirmedVocabulary), ["XPay", "SwiftData"])
            XCTAssertEqual(Set(record.vocabulary.map(\.id)), identities)
            XCTAssertEqual(other.userTitle, "Pending title")
            XCTAssertEqual(try history.context.fetchCount(FetchDescriptor<MeetingVocabularyTerm>()), 2)
        }
        try history.replaceVocabulary(["New", "SwiftData"], in: record)
        XCTAssertEqual(record.confirmedVocabulary, ["New", "SwiftData"])
        XCTAssertEqual(try history.context.fetchCount(FetchDescriptor<MeetingVocabularyTerm>()), 2)
    }

    func testMeetingEditsAndRemovalsPersistWithoutChangingOtherScopes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "vocabulary.store")
        let defaults = Phase2Fixture.defaults(self)
        let personal = SpeechVocabularySettings(defaults: defaults)
        personal.save(["Personal"])
        let id: UUID
        do {
            let history = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
            let record = try history.createDraft(languagePair: .englishToEnglish)
            let other = try history.createDraft(languagePair: .englishToEnglish)
            id = record.id
            let coordinator = CaptureCoordinator(speechVocabularySettings: personal, defaults: defaults)
            coordinator.history = history
            let editor = coordinator.vocabularyEditor(for: record, settings: AISettings(defaults: defaults))
            editor.manualText = "XPay\nSwiftData"
            editor.addTerms()
            let swiftDataID = record.vocabulary.first { $0.phrase == "SwiftData" }!.id
            editor.beginEditing("XPay")
            editor.editedText = "XPay Pro"
            editor.saveEdit()
            XCTAssertEqual(record.vocabulary.first { $0.phrase == "SwiftData" }?.id, swiftDataID)
            editor.remove("SwiftData")
            XCTAssertEqual(record.confirmedVocabulary, ["XPay Pro"])
            XCTAssertTrue(other.confirmedVocabulary.isEmpty)
            XCTAssertEqual(personal.phrases, ["Personal"])
            XCTAssertEqual(try history.context.fetchCount(FetchDescriptor<MeetingVocabularyTerm>()), 1)
        }
        let reopened = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
        XCTAssertEqual(try reopened.record(id: id)?.confirmedVocabulary, ["XPay Pro"])
    }
}
