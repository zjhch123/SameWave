import Foundation
import Observation

/// App-session editing state; the presentation never owns extraction or uncommitted text.
@MainActor
@Observable
final class VocabularyEditorStore {
    enum Scope { case meeting, personal }
    enum Focus: Hashable { case manual, saved, candidate(UUID) }
    var focusedField: Focus?
    let scope: Scope
    let importer: VocabularyImportController
    private let readPhrases: () -> [String]
    private let replacePhrases: ([String]) throws -> Void

    var manualText = ""
    var isAddingTerms = false
    var editingPhrase: String?
    var editedText = ""
    private(set) var vocabularyError: String?
    private(set) var vocabularyMessage: String?
    var filesExpanded = false
    var showsBottomActions = false
    var scrollOffset: CGFloat = 0
    private(set) var documents: [VocabularySourceDocument] = []
    private(set) var isLoadingFiles = false
    private(set) var fileError: String?
    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var loadingToken = UUID()

    var title: String { scope == .meeting ? "Meeting Vocabulary" : "Personal Vocabulary" }
    var scopeLabel: String { scope == .meeting ? "This meeting" : "Across meetings" }
    var phrases: [String] { readPhrases() }
    var manualPhrases: [String] { SpeechVocabularySettings.phrases(from: manualText) }
    var hasInvalidManualInput: Bool { manualPhrases.contains { !VocabularyGenerator.isValidPhrase($0) } }

    convenience init(aiSettings: AISettings, settings: SpeechVocabularySettings) {
        self.init(scope: .personal, aiSettings: aiSettings,
                  readPhrases: { settings.phrases }, replacePhrases: { settings.save($0) })
    }

    init(scope: Scope, aiSettings: AISettings, readPhrases: @escaping () -> [String],
         replacePhrases: @escaping ([String]) throws -> Void) {
        self.scope = scope
        self.readPhrases = readPhrases
        self.replacePhrases = replacePhrases
        importer = VocabularyImportController(aiSettings: aiSettings, existingPhrases: readPhrases,
            saveCandidates: { candidates in
                let current = readPhrases()
                let additions = SpeechVocabularySettings.newPhrases(from: candidates.map(\.text), excluding: current)
                if !additions.isEmpty { try replacePhrases(current + additions) }
                return additions.count
            })
    }

    func addTerms() {
        guard !manualPhrases.isEmpty, !hasInvalidManualInput else { return }
        let current = phrases
        let additions = SpeechVocabularySettings.newPhrases(from: manualPhrases, excluding: current)
        let skipped = manualText.components(separatedBy: .newlines).filter { !$0.trimmed.isEmpty }.count - additions.count
        commit {
            if !additions.isEmpty { try replacePhrases(current + additions) }
            manualText = ""
            isAddingTerms = false
            vocabularyMessage = "Added \(additions.count) \(additions.count == 1 ? "term" : "terms")"
                + (skipped > 0 ? " · Skipped \(skipped) duplicates" : "")
        }
    }

    func beginEditing(_ phrase: String) {
        // A pending row must be saved or cancelled explicitly before editing another.
        guard editingPhrase == nil else { return }
        editingPhrase = phrase
        editedText = phrase
        vocabularyError = nil
    }

    func cancelEditing() {
        editingPhrase = nil
        editedText = ""
        vocabularyError = nil
    }

    func saveEdit() {
        guard let original = editingPhrase, VocabularyGenerator.isValidPhrase(editedText) else { return }
        let replacement = editedText.trimmed
        guard let index = phrases.firstIndex(of: original) else {
            vocabularyError = "This term is no longer available. Cancel this edit and try again."
            return
        }
        var updated = phrases
        updated[index] = replacement
        let normalized = SpeechVocabularySettings.normalized(updated)
        commit {
            try replacePhrases(normalized)
            cancelEditing()
            vocabularyMessage = normalized.count < updated.count ? "Duplicate merged" : "Term saved"
        }
    }

    func remove(_ phrase: String) {
        commit {
            try replacePhrases(phrases.filter { $0 != phrase })
            if editingPhrase == phrase { cancelEditing() }
            vocabularyMessage = "Term removed"
        }
    }

    private func commit(_ operation: () throws -> Void) {
        do { try operation(); vocabularyError = nil }
        catch {
            vocabularyMessage = nil
            vocabularyError = "Could not save terms. Your edits are retained. \(error.localizedDescription)"
        }
    }

    /// File selection is local and does not configure or call a provider.
    func chooseFiles(_ selection: Result<[URL], Error>) {
        guard !isLoadingFiles else { return }
        let urls: [URL]
        do { urls = try selection.get() }
        catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                fileError = error.localizedDescription
            }
            return
        }
        guard !urls.isEmpty else { return }
        isLoadingFiles = true
        fileError = nil
        let token = loadingToken
        loadingTask = Task {
            do {
                let loaded = try await VocabularyDocumentLoader.load(urls)
                try Task.checkCancellation()
                guard token == loadingToken else { return }
                documents = try VocabularyDocumentLoader.merging(loaded, into: documents)
                filesExpanded = true
            } catch is CancellationError { return }
            catch { if token == loadingToken { fileError = error.localizedDescription } }
            if token == loadingToken { isLoadingFiles = false; loadingTask = nil }
        }
    }

    func removeDocument(at index: Int) {
        guard documents.indices.contains(index) else { return }
        documents.remove(at: index)
        fileError = nil
    }

    func invalidate() {
        loadingToken = UUID()
        loadingTask?.cancel()
        loadingTask = nil
        isLoadingFiles = false
        importer.reset()
        documents = []
        manualText = ""
        cancelEditing()
    }
}
