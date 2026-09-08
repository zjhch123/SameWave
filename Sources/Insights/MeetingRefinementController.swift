import Foundation
import Observation

/// App-session work for one saved meeting. Views only observe and start it.
@MainActor
@Observable
final class MeetingRefinementController {
    let refiner: TranscriptRefiner
    private(set) var isRefining = false
    private(set) var isGeneratingTitle = false
    private(set) var errorMessage: String?
    private(set) var titleErrorMessage: String?
    private let meetingID: UUID
    private let history: MeetingHistoryStore
    private let providerFactory: () -> (any LLMProvider)?
    @ObservationIgnored private var refinementTask: Task<Void, Never>?
    @ObservationIgnored private var titleTask: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()

    init(meetingID: UUID, settings: AISettings, vocabulary: SpeechVocabularySettings,
         history: MeetingHistoryStore, providerFactory: (() -> (any LLMProvider)?)? = nil) {
        self.meetingID = meetingID
        self.history = history
        self.providerFactory = providerFactory ?? { settings.makeProvider() }
        refiner = TranscriptRefiner(settings: settings, vocabularySettings: vocabulary,
                                    providerFactory: providerFactory)
    }

    func start() {
        guard !isRefining else { return }
        do {
            guard let record = try history.record(id: meetingID), record.meetingStatus == .ended else { return }
            let expectedToken = token
            let lines = record.lines
            let languagePair = record.languagePair
            let glossary = record.glossaryJSON
            errorMessage = nil
            isRefining = true
            refinementTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if token == expectedToken { isRefining = false; refinementTask = nil }
                }
                do {
                    let outcome = try await refiner.refine(lines: lines, languagePair: languagePair,
                                                          priorGlossaryJSON: glossary)
                    try Task.checkCancellation()
                    guard token == expectedToken, let owner = try history.record(id: meetingID) else { return }
                    try history.saveRefinement(outcome, to: owner)
                } catch {
                    guard token == expectedToken, !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                }
            }
            if record.needsAITitle && !isGeneratingTitle {
                titleErrorMessage = nil
                isGeneratingTitle = true
                let provider = providerFactory()
                titleTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    defer {
                        if token == expectedToken { isGeneratingTitle = false; titleTask = nil }
                    }
                    do {
                        guard let title = try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: provider) else { return }
                        try Task.checkCancellation()
                        guard token == expectedToken, let owner = try history.record(id: meetingID),
                              owner.needsAITitle else { return }
                        try history.saveGeneratedTitle(title, to: owner)
                    } catch {
                        guard token == expectedToken, !Task.isCancelled, record.needsAITitle else { return }
                        titleErrorMessage = String(localized: "Title generation failed. Transcript refinement is unaffected. \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        token = UUID()
        refinementTask?.cancel()
        titleTask?.cancel()
        refinementTask = nil
        titleTask = nil
        refiner.cancel()
        isRefining = false
        isGeneratingTitle = false
        errorMessage = nil
        titleErrorMessage = nil
    }
}
