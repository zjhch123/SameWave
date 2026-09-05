import Foundation
import Observation

struct VocabularyCandidate: Identifiable, Equatable {
    let id = UUID()
    let originalPhrase: String
    var text: String
    var isSelected = true
    var sources: [VocabularySourceExcerpt]
}

struct VocabularyImportRequest: Equatable {
    enum Status: Equatable {
        case pending, succeeded, failed(String)
    }
    let batch: VocabularyBatch
    var status: Status = .pending
}

@MainActor
@Observable
final class VocabularyImportController {
    enum State: Equatable {
        case idle, preparing, generating, reviewing
        case failed(String)
    }

    private let aiSettings: AISettings
    private let vocabularyDraft: SpeechVocabularyDraft
    @ObservationIgnored private var provider: (any LLMProvider)?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationToken = UUID()
    @ObservationIgnored private var seenOriginals: Set<String> = []

    var candidates: [VocabularyCandidate] = []
    private(set) var state: State = .idle
    private(set) var requests: [VocabularyImportRequest] = []
    private(set) var attempts: [VocabularyAttempt] = []
    private(set) var discoveredCount = 0
    private(set) var savedMessage: String?

    init(aiSettings: AISettings, vocabularyDraft: SpeechVocabularyDraft) {
        self.aiSettings = aiSettings
        self.vocabularyDraft = vocabularyDraft
    }

    var isConfigured: Bool { aiSettings.isConfigured }
    var isRunning: Bool { state == .preparing || state == .generating }
    var hasActiveWorkflow: Bool { state != .idle || !requests.isEmpty }
    var canStartOrResume: Bool { isConfigured || hasActiveWorkflow }
    var completedCount: Int { requests.filter { $0.status != .pending }.count }
    var failedCount: Int {
        requests.filter { if case .failed = $0.status { return true }; return false }.count
    }
    var incompleteCount: Int { requests.filter { $0.status != .succeeded }.count }
    var canRetry: Bool { !isRunning && incompleteCount > 0 && provider != nil }
    var hasInvalidSelection: Bool {
        candidates.contains { $0.isSelected && !VocabularyGenerator.isValidPhrase($0.text) }
    }
    var selectedPhrases: [String] {
        VocabularyCandidateReview.newPhrases(
            from: candidates.filter { $0.isSelected && VocabularyGenerator.isValidPhrase($0.text) }.map(\.text),
            excluding: vocabularyDraft.existingPhrases
        )
    }

    @discardableResult
    func handleFileSelection(_ result: Result<[URL], Error>) -> Bool {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return false }
            guard let provider = aiSettings.makeProvider() else {
                state = .failed(LLMError.notConfigured.localizedDescription)
                return true
            }
            start(from: urls, using: provider)
            return true
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return false
            }
            state = .failed(error.localizedDescription)
            return true
        }
    }

    func start(from urls: [URL], using provider: any LLMProvider) {
        close()
        self.provider = provider
        state = .preparing
        let token = generationToken
        let previousTask = generationTask
        generationTask = Task {
            // A cancelled provider must finish unwinding before another run starts.
            await previousTask?.value
            do {
                try Task.checkCancellation()
                let documents = try await VocabularyDocumentLoader.load(urls)
                let batches = try await VocabularyGenerator.prepare(from: documents)
                try Task.checkCancellation()
                guard generationToken == token else { return }
                requests = batches.map { VocabularyImportRequest(batch: $0) }
                await runPending(using: provider, token: token)
            } catch {
                guard generationToken == token else { return }
                state = error is CancellationError ? .idle : .failed(error.localizedDescription)
            }
            if generationToken == token { generationTask = nil }
        }
    }

    func stop() {
        generationToken = UUID()
        generationTask?.cancel()
        if let index = attempts.lastIndex(where: { $0.outcome == .running }) {
            attempts[index].finish(.cancelled)
        }
        state = candidates.isEmpty ? .idle : .reviewing
    }

    func close() {
        stop()
        candidates = []
        requests = []
        attempts = []
        seenOriginals = []
        discoveredCount = 0
        savedMessage = nil
        provider = nil
        state = .idle
    }

    func retryIncomplete() {
        guard canRetry, let provider else { return }
        let previousTask = generationTask
        generationToken = UUID()
        let token = generationToken
        for index in requests.indices where requests[index].status != .succeeded {
            requests[index].status = .pending
        }
        state = .generating
        generationTask = Task {
            await previousTask?.value
            await runPending(using: provider, token: token)
            if generationToken == token { generationTask = nil }
        }
    }

    func selectAll(_ selected: Bool) {
        for index in candidates.indices { candidates[index].isSelected = selected }
    }

    func saveSelected() {
        guard !hasInvalidSelection else { return }
        let selectedIDs = Set(candidates.filter(\.isSelected).map(\.id))
        let added = vocabularyDraft.saveImported(selectedPhrases)
        candidates.removeAll { selectedIDs.contains($0.id) }
        savedMessage = added > 0 ? "New terms saved: \(added)" : "All selected terms already exist; no duplicates were added"
    }

    private func runPending(using provider: any LLMProvider, token: UUID) async {
        guard generationToken == token, !Task.isCancelled else { return }
        state = .generating
        let pending = requests.filter { $0.status == .pending }.map(\.batch)
        do {
            try await VocabularyGenerator(provider: provider).generate(
                batches: pending, totalBatchCount: requests.count
            ) { event in
                guard self.generationToken == token else { return }
                self.receive(event)
            }
            guard generationToken == token else { return }
            state = .reviewing
        } catch {
            guard generationToken == token else { return }
            if error is CancellationError {
                state = candidates.isEmpty ? .idle : .reviewing
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func receive(_ event: VocabularyGenerationEvent) {
        switch event {
        case .attempt(let attempt):
            if let index = attempts.firstIndex(where: { $0.id == attempt.id }) {
                attempts[index] = attempt
            } else {
                attempts.append(attempt)
            }
        case .succeeded(let number, let phrases):
            guard let index = requests.firstIndex(where: { $0.batch.number == number }) else { return }
            requests[index].status = .succeeded
            merge(phrases, from: requests[index].batch)
        case .failed(let number, let message):
            guard let index = requests.firstIndex(where: { $0.batch.number == number }) else { return }
            requests[index].status = .failed(message)
        }
    }

    private func merge(_ phrases: [String], from batch: VocabularyBatch) {
        let existing = Set((vocabularyDraft.existingPhrases + candidates.map(\.text)).map(Self.identity))
        for phrase in phrases {
            let key = Self.identity(phrase)
            let sources = batch.excerpts(for: phrase)
            if let index = candidates.firstIndex(where: { Self.identity($0.originalPhrase) == key }) {
                for source in sources where !candidates[index].sources.contains(source) {
                    candidates[index].sources.append(source)
                }
            }
            guard seenOriginals.insert(key).inserted, !existing.contains(key) else { continue }
            candidates.append(VocabularyCandidate(originalPhrase: phrase, text: phrase, sources: sources))
            discoveredCount += 1
        }
    }

    private static func identity(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
