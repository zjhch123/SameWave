import Foundation
import Observation

struct VocabularyCandidate: Identifiable, Equatable {
    let id = UUID()
    let originalPhrase: String
    var text: String
    var isSelected = true
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
    private let existingPhrases: () -> [String]
    private let saveCandidates: ([VocabularyCandidate]) throws -> Int
    @ObservationIgnored private var provider: (any LLMProvider)?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationToken = UUID()
    @ObservationIgnored private var seenOriginals: Set<String> = []

    var candidates: [VocabularyCandidate] = []
    private(set) var state: State = .idle
    private(set) var requests: [VocabularyImportRequest] = []
    private(set) var currentAttempt: VocabularyAttempt?
    private(set) var discoveredCount = 0
    private(set) var savedMessage: String?
    private(set) var saveError: String?

    init(aiSettings: AISettings, existingPhrases: @escaping () -> [String],
         saveCandidates: @escaping ([VocabularyCandidate]) throws -> Int) {
        self.aiSettings = aiSettings
        self.existingPhrases = existingPhrases
        self.saveCandidates = saveCandidates
    }

    var isConfigured: Bool { aiSettings.isConfigured }
    var isRunning: Bool { state == .preparing || state == .generating }
    var completedCount: Int { requests.filter { $0.status != .pending }.count }
    var incompleteCount: Int { requests.filter { $0.status != .succeeded }.count }
    var generationError: String? {
        if case .failed(let message) = state { return message }
        for request in requests.reversed() {
            if case .failed(let message) = request.status { return message }
        }
        return nil
    }
    var canRetry: Bool { !isRunning && incompleteCount > 0 && provider != nil }
    var hasInvalidSelection: Bool {
        candidates.contains { $0.isSelected && !VocabularyGenerator.isValidPhrase($0.text) }
    }
    func start(from urls: [URL], using provider: any LLMProvider) {
        start(using: provider) { try await VocabularyDocumentLoader.load(urls) }
    }

    func start(documents: [VocabularySourceDocument]) {
        guard let provider = aiSettings.makeProvider() else {
            state = .failed(LLMError.notConfigured.localizedDescription)
            return
        }
        start(using: provider) { documents }
    }

    private func start(using provider: any LLMProvider,
                       load: @escaping @MainActor () async throws -> [VocabularySourceDocument]) {
        reset()
        self.provider = provider
        state = .preparing
        let token = generationToken
        let previousTask = generationTask
        generationTask = Task {
            // A cancelled provider must finish unwinding before another run starts.
            await previousTask?.value
            do {
                try Task.checkCancellation()
                let documents = try await load()
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
        currentAttempt = nil
        state = candidates.isEmpty ? .idle : .reviewing
    }

    func reset() {
        stop()
        candidates = []
        requests = []
        seenOriginals = []
        discoveredCount = 0
        savedMessage = nil
        saveError = nil
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

    func discardSuggestions() {
        guard !isRunning else { return }
        reset()
        savedMessage = "Suggestions discarded"
    }

    func selectAll(_ selected: Bool) {
        for index in candidates.indices { candidates[index].isSelected = selected }
    }

    func saveSelected() {
        guard !hasInvalidSelection else { return }
        let selectedIDs = Set(candidates.filter(\.isSelected).map(\.id))
        guard !selectedIDs.isEmpty else { return }
        do {
            let added = try saveCandidates(candidates.filter { $0.isSelected })
            candidates.removeAll { selectedIDs.contains($0.id) }
            saveError = nil
            savedMessage = added > 0 ? "New terms saved: \(added)" : "All selected terms already exist; no duplicates were added"
        } catch {
            savedMessage = nil
            saveError = "Could not save terms. Your selection is retained; try adding the terms again. \(error.localizedDescription)"
        }
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
            currentAttempt = nil
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
            currentAttempt = attempt
        case .succeeded(let number, let phrases):
            guard let index = requests.firstIndex(where: { $0.batch.number == number }) else { return }
            currentAttempt = nil
            requests[index].status = .succeeded
            merge(phrases)
        case .failed(let number, let message):
            guard let index = requests.firstIndex(where: { $0.batch.number == number }) else { return }
            currentAttempt = nil
            requests[index].status = .failed(message)
        }
    }

    private func merge(_ phrases: [String]) {
        let existing = Set((existingPhrases() + candidates.map(\.text)).map(SpeechVocabularySettings.identity))
        for phrase in phrases {
            let key = SpeechVocabularySettings.identity(phrase)
            guard seenOriginals.insert(key).inserted, !existing.contains(key) else { continue }
            candidates.append(VocabularyCandidate(originalPhrase: phrase, text: phrase))
            discoveredCount += 1
        }
    }

}
