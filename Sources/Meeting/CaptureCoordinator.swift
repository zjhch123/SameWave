import Foundation
import Observation

/// Orchestrates the meeting lifecycle and the capture → ASR → transcript →
/// translation/persistence pipeline. Domain state stays in `CaptionStore`; platform
/// objects and lifecycle transitions stay here.
@MainActor
@Observable
final class CaptureCoordinator {
    var sourceLanguage: MeetingLanguage = .english
    var targetLanguage: MeetingLanguage = .simplifiedChinese
    private(set) var captionMyMic = true
    private(set) var sessionState: MeetingSessionState = .idle
    private(set) var statusMessage = ""
    private(set) var sessionStartedAt: Date?
    /// nil shows the mounted session, or the empty state when none is mounted.
    var selectedHistoryRecord: MeetingRecord? {
        didSet {
            if oldValue?.id != selectedHistoryRecord?.id {
                if let id = oldValue?.id { insights?.cancelMeeting(id) }
                if selectedHistoryRecord != nil, let id = activeRecordID { insights?.cancelMeeting(id) }
                if selectedHistoryRecord == nil, sessionState == .recording, let activeRecord {
                    insights?.startRecording(activeRecord, sections: store.sections)
                }
            }
            persistSelection()
        }
    }

    private var pausedElapsed: TimeInterval = 0
    private var meetingStartedAt: Date?
    private var sessionID = UUID()

    var elapsedSeconds: TimeInterval {
        pausedElapsed + (sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    var isRunning: Bool { sessionState.hasActiveSession }
    var isPaused: Bool { sessionState == .paused }
    var isTransitioning: Bool {
        sessionState == .starting || sessionState == .pausing || sessionState == .stopping
    }

    let store = CaptionStore()
    let translation = TranslationBridge()

    private let speechVocabularySettings: SpeechVocabularySettings
    private let defaults: UserDefaults
    private static let selectedMeetingKey = "selectedMeetingID"
    private var activeVocabulary: [String] = []
    var history: MeetingHistoryStore?
    var insights: InsightEngine?
    var refiner: TranscriptRefiner?
    var titleGenerator: MeetingTitleGenerator?
    @ObservationIgnored private var vocabularyEditors: [UUID: VocabularyEditorStore] = [:]

    private var activeRecord: MeetingRecord? {
        didSet { persistSelection() }
    }
    private var autosaveTask: Task<Void, Never>?
    var activeRecordID: UUID? { activeRecord?.id }
    var workspaceRecord: MeetingRecord? { selectedHistoryRecord ?? activeRecord }
    var globalVocabulary: [String] { speechVocabularySettings.phrases }
    var selectedRecordID: UUID? { selectedHistoryRecord?.id ?? activeRecordID }
    var languagePair: MeetingLanguagePair {
        MeetingLanguagePair(source: sourceLanguage, target: targetLanguage)
    }

    private var systemCapture: SystemAudioCaptureSCK?
    private var systemSpeech: NativeSpeechEngine?
    private var microphoneCapture: MicrophoneCapture?
    private var microphoneSpeech: NativeSpeechEngine?
    private var isChangingMicrophone = false
    private var lastProvisionalText: [Speaker: String] = [:]

    init(speechVocabularySettings: SpeechVocabularySettings, defaults: UserDefaults = .standard) {
        self.speechVocabularySettings = speechVocabularySettings
        self.defaults = defaults
        translation.onTranslated = { [weak self] request, translated in
            guard let self, request.sessionID == self.sessionID else { return }
            self.store.applyTranslation(
                translated,
                id: request.sectionId,
                generation: request.generation,
                final: request.isFinal
            )
            self.persistTranslationIfPaused()
        }
        translation.onFailed = { [weak self] request in
            guard let self, request.sessionID == self.sessionID else { return }
            self.store.failTranslation(id: request.sectionId, generation: request.generation)
            self.statusMessage = "Translation is temporarily unavailable. Source text has been kept."
            self.persistTranslationIfPaused()
        }
    }

    /// One editing session per meeting, independent of the sheet lifecycle.
    func vocabularyEditor(for record: MeetingRecord, settings: AISettings) -> VocabularyEditorStore {
        if let editor = vocabularyEditors[record.id] { return editor }
        let meetingID = record.id
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: settings,
            readPhrases: { record.confirmedVocabulary },
            replacePhrases: { [weak self] phrases in
                guard let history = self?.history, let owner = try history.record(id: meetingID) else {
                    throw LLMError.invalidRequest("This meeting is no longer available.")
                }
                try history.replaceVocabulary(phrases, in: owner)
            })
        vocabularyEditors[meetingID] = editor
        return editor
    }

    // MARK: - Lifecycle

    func startGlobal() async {
        guard sessionState == .idle else { return }
        guard let history else {
            statusMessage = "Cannot start a meeting because the history database is unavailable"
            return
        }

        do {
            if activeRecord == nil { activeRecord = try history.createDraft(languagePair: languagePair) }
            guard let record = activeRecord else { return }
            try history.beginCapture(record, languagePair: languagePair)
        } catch {
            statusMessage = "Could not save the meeting: \(error.localizedDescription)"
            return
        }
        beginFreshSession()
        selectedHistoryRecord = nil
        let expectedSessionID = sessionID
        do {
            try await startSystemPipeline(sessionID: expectedSessionID)
        } catch {
            guard sessionID == expectedSessionID, sessionState == .starting else { return }
            var message = error.localizedDescription
            await tearDownPipelines()
            let preparedRecord = activeRecord
            resetSession(keepingTranscript: false)
            activeRecord = preparedRecord
            do {
                if let preparedRecord { try history.setStatus(preparedRecord, .draft) }
            } catch {
                message += "; could not save the draft: \(error.localizedDescription)"
            }
            statusMessage = message
            return
        }

        if captionMyMic {
            do {
                try await startMicrophonePipeline(sessionID: expectedSessionID)
            } catch {
                guard sessionID == expectedSessionID, sessionState == .starting else { return }
                if !(error is CancellationError) {
                    statusMessage = "Microphone unavailable; recording system audio only: \(error.localizedDescription)"
                }
            }
        }

        guard sessionID == expectedSessionID, sessionState == .starting else { return }
        sessionState = .recording
        if statusMessage == "Starting…" || statusMessage == "Model ready" {
            statusMessage = "Listening to system audio…"
        }
        startAutosave()
    }

    @discardableResult
    func pause() async -> Bool {
        guard sessionState == .recording else { return false }
        freezeElapsedTime()
        if let id = activeRecordID { insights?.cancelMeeting(id) }
        sessionState = .pausing
        statusMessage = "Pausing…"

        await tearDownPipelines()
        sealOpenTurn()
        lastProvisionalText.removeAll()
        let translationsFinished = await translation.waitUntilIdle(timeout: .seconds(5))

        sessionState = .paused
        do {
            try persistActiveRecord(status: .paused)
            statusMessage = translationsFinished ? "Paused" : "Paused; some translations are incomplete"
            return true
        } catch {
            statusMessage = "Paused, but saving failed: \(error.localizedDescription)"
            return false
        }
    }

    func resume() async {
        guard sessionState == .paused, let activeRecord else { return }
        activeVocabulary = sourceLanguage == .english
            ? activeRecord.effectiveVocabulary(global: globalVocabulary) : []
        sessionState = .starting
        sessionStartedAt = Date()
        statusMessage = "Starting…"
        let expectedSessionID = sessionID

        do {
            try history?.setStatus(activeRecord, .recording)
            try await startSystemPipeline(sessionID: expectedSessionID)
        } catch {
            guard sessionID == expectedSessionID, sessionState == .starting else { return }
            await tearDownPipelines()
            sessionStartedAt = nil
            sessionState = .paused
            do {
                try history?.setStatus(activeRecord, .paused)
            } catch {
                statusMessage = "Could not resume or save the paused state: \(error.localizedDescription)"
                return
            }
            statusMessage = "Could not resume: \(error.localizedDescription)"
            return
        }

        if captionMyMic {
            do {
                try await startMicrophonePipeline(sessionID: expectedSessionID)
            } catch {
                guard sessionID == expectedSessionID, sessionState == .starting else { return }
                if !(error is CancellationError) {
                    statusMessage = "Microphone unavailable; recording system audio only: \(error.localizedDescription)"
                }
            }
        }
        guard sessionID == expectedSessionID, sessionState == .starting else { return }
        sessionState = .recording
        if statusMessage == "Starting…" || statusMessage == "Model ready" {
            statusMessage = "Listening to system audio…"
        }
        startAutosave()
    }

    func stop() async {
        guard sessionState.hasActiveSession, sessionState != .stopping else { return }
        if sessionStartedAt != nil { freezeElapsedTime() }
        if let id = activeRecordID { insights?.cancelMeeting(id) }
        sessionState = .stopping
        statusMessage = "Finishing…"

        await tearDownPipelines()
        sealOpenTurn()
        let translationsFinished = await translation.waitUntilIdle(timeout: .seconds(5))
        let endedAt = currentEndedAt()

        guard let record = activeRecord, let history else {
            resetSession(keepingTranscript: true)
            return
        }
        do {
            try history.finish(record, sections: store.sections, endedAt: endedAt)
        } catch {
            sessionState = .paused
            statusMessage = "Could not save the meeting. Try ending it again: \(error.localizedDescription)"
            return
        }

        selectedHistoryRecord = record
        resetSession(keepingTranscript: true)
        statusMessage = translationsFinished ? "" : "Source text saved; some translations are incomplete"
    }

    func startNewMeeting() async {
        guard await suspendCurrent() else { return }
        guard let history else { return }
        do {
            let draft = try history.createDraft(languagePair: languagePair)
            mountDraft(draft)
            selectedHistoryRecord = nil
        } catch {
            statusMessage = "Could not create the meeting: \(error.localizedDescription)"
        }
    }

    func loadSession(_ record: MeetingRecord) async {
        guard record.meetingStatus != .ended, record.id != activeRecord?.id else { return }
        guard await suspendCurrent() else { return }
        do {
            if record.meetingStatus == .draft { mountDraft(record) }
            else { try mountPaused(record) }
            selectedHistoryRecord = nil
        } catch {
            statusMessage = "Could not restore the meeting: \(error.localizedDescription)"
        }
    }

    func openHistory(_ record: MeetingRecord) async {
        guard record.meetingStatus == .ended, await suspendCurrent() else { return }
        resetSession(keepingTranscript: false)
        selectedHistoryRecord = record
    }

    func restoreSelection() {
        guard sessionState == .idle, let history else { return }
        do {
            let records = try history.unfinishedRecords()
            for record in records where record.meetingStatus == .recording {
                record.status = MeetingStatus.paused.rawValue
            }
            try history.save()

            let savedID = defaults.string(forKey: Self.selectedMeetingKey).flatMap(UUID.init(uuidString:))
            let savedRecord = try savedID.flatMap { try history.record(id: $0) }
            guard let record = try savedRecord ?? history.mostRecentRecord() else {
                defaults.removeObject(forKey: Self.selectedMeetingKey)
                return
            }
            try selectStoredRecord(record)
        } catch {
            statusMessage = "Could not restore the previous meeting: \(error.localizedDescription)"
        }
    }

    func delete(_ record: MeetingRecord) {
        guard !(record.id == activeRecordID && isRunning), let history else { return }
        let wasCurrent = selectedRecordID == record.id
        do {
            let wasActive = record.id == activeRecordID
            let wasSelected = selectedHistoryRecord?.id == record.id
            insights?.cancelMeeting(record.id)
            try history.delete(record)
            vocabularyEditors.removeValue(forKey: record.id)?.invalidate()
            insights?.cancelMeeting(record.id, deleting: true)
            if wasActive { resetSession(keepingTranscript: false) }
            if wasSelected {
                selectedHistoryRecord = nil
                if activeRecord == nil { resetSession(keepingTranscript: false) }
            }
        } catch {
            statusMessage = "Could not delete: \(error.localizedDescription)"
            return
        }
        if wasCurrent && selectedRecordID == nil {
            do {
                if let next = try history.mostRecentRecord() { try selectStoredRecord(next) }
            } catch {
                statusMessage = "Meeting deleted, but another meeting could not be opened: \(error.localizedDescription)"
            }
        }
    }

    private func selectStoredRecord(_ record: MeetingRecord) throws {
        switch record.meetingStatus {
        case .ended:
            resetSession(keepingTranscript: false)
            selectedHistoryRecord = record
        case .draft:
            mountDraft(record)
            selectedHistoryRecord = nil
        case .paused, .recording:
            try mountPaused(record)
            selectedHistoryRecord = nil
        }
    }

    func persistNow() {
        do {
            try persistActiveRecord(status: sessionState == .recording ? .recording : .paused)
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Capture pipelines

    private func startSystemPipeline(sessionID expectedSessionID: UUID) async throws {
        let speech = makeSpeechEngine(for: .remote, sessionID: expectedSessionID)
        let capture = SystemAudioCaptureSCK(
            onAudio: speech.feed,
            onError: { [weak self] error in
                Task { @MainActor in
                    await self?.handleCaptureError(
                        error,
                        speaker: .remote,
                        sessionID: expectedSessionID
                    )
                }
            }
        )
        systemSpeech = speech
        systemCapture = capture
        try await speech.load()
        guard expectedSessionID == sessionID, sessionState == .starting else {
            await speech.stop()
            throw CancellationError()
        }
        try await capture.start()
        guard expectedSessionID == sessionID, sessionState == .starting else {
            await capture.stop()
            await speech.stop()
            throw CancellationError()
        }
    }

    private func startMicrophonePipeline(sessionID expectedSessionID: UUID) async throws {
        guard microphoneCapture == nil else { return }
        let speech = makeSpeechEngine(for: .mine, sessionID: expectedSessionID)
        let capture = MicrophoneCapture()
        capture.onAudio = speech.feed
        capture.onError = { [weak self] error in
            Task { @MainActor in
                await self?.handleCaptureError(
                    error,
                    speaker: .mine,
                    sessionID: expectedSessionID
                )
            }
        }
        microphoneSpeech = speech
        microphoneCapture = capture

        do {
            try await speech.load()
            guard expectedSessionID == sessionID,
                  captionMyMic,
                  sessionState == .starting || sessionState == .recording else {
                throw CancellationError()
            }
            try await capture.start()
            guard expectedSessionID == sessionID,
                  captionMyMic,
                  sessionState == .starting || sessionState == .recording else {
                throw CancellationError()
            }
        } catch {
            capture.stop()
            await speech.stop()
            if microphoneCapture === capture { microphoneCapture = nil }
            if microphoneSpeech === speech { microphoneSpeech = nil }
            throw error
        }
    }

    private func tearDownPipelines() async {
        autosaveTask?.cancel()
        autosaveTask = nil

        if let systemCapture { await systemCapture.stop() }
        microphoneCapture?.stop()
        self.systemCapture = nil
        microphoneCapture = nil

        await systemSpeech?.stop()
        await microphoneSpeech?.stop()
        systemSpeech = nil
        microphoneSpeech = nil
    }

    private func stopMicrophonePipeline() async {
        let capture = microphoneCapture
        let speech = microphoneSpeech
        microphoneCapture = nil
        microphoneSpeech = nil
        capture?.stop()
        await speech?.stop()
        if !captionMyMic { sealTurn(.mine) }
    }

    func setCaptionMyMic(_ enabled: Bool) async {
        guard enabled != captionMyMic, !isChangingMicrophone else { return }
        isChangingMicrophone = true
        defer { isChangingMicrophone = false }
        captionMyMic = enabled
        guard sessionState == .recording else { return }
        if enabled {
            let expectedSessionID = sessionID
            do {
                try await startMicrophonePipeline(sessionID: expectedSessionID)
            } catch {
                guard sessionID == expectedSessionID else { return }
                captionMyMic = false
                if !(error is CancellationError) {
                    statusMessage = "Microphone unavailable: \(error.localizedDescription)"
                }
            }
        } else {
            await stopMicrophonePipeline()
        }
    }

    private func makeSpeechEngine(for speaker: Speaker, sessionID expectedSessionID: UUID) -> NativeSpeechEngine {
        NativeSpeechEngine(
            localeID: sourceLanguage.localeID,
            contextualStrings: activeVocabulary,
            onInterim: { [weak self] text in
                await self?.receiveInterim(text, speaker: speaker, sessionID: expectedSessionID)
            },
            onCommit: { [weak self] text in
                await self?.receiveCommit(text, speaker: speaker, sessionID: expectedSessionID)
            },
            onStatus: { [weak self] status in
                guard speaker == .remote else { return }
                await self?.receiveSpeechStatus(status, sessionID: expectedSessionID)
            }
        )
    }

    private func receiveInterim(_ text: String, speaker: Speaker, sessionID expectedSessionID: UUID) {
        guard sessionID == expectedSessionID else { return }
        handleInterim(text, speaker: speaker)
    }

    private func receiveCommit(_ text: String, speaker: Speaker, sessionID expectedSessionID: UUID) {
        guard sessionID == expectedSessionID else { return }
        handleCommit(text, speaker: speaker)
    }

    private func receiveSpeechStatus(_ status: String, sessionID expectedSessionID: UUID) {
        guard sessionID == expectedSessionID else { return }
        statusMessage = status
    }

    private func handleCaptureError(
        _ error: Error,
        speaker: Speaker,
        sessionID expectedSessionID: UUID
    ) async {
        guard sessionID == expectedSessionID else { return }
        guard sessionState == .recording || sessionState == .starting else { return }
        if speaker == .remote {
            statusMessage = "System audio error: \(error.localizedDescription)"
        } else {
            statusMessage = "Microphone error; microphone captions stopped: \(error.localizedDescription)"
            captionMyMic = false
            await stopMicrophonePipeline()
        }
    }

    // MARK: - Transcript and translation

    private func handleInterim(_ text: String, speaker: Speaker) {
        guard sessionState == .recording || sessionState == .starting else { return }
        let text = text.trimmed
        guard !text.isEmpty else { return }
        let (sectionID, sealedID) = store.updateInterim(text, speaker: speaker)
        if let sealedID { scheduleTranslation(id: sealedID, final: true) }
        guard let sectionID else { return }

        if languagePair.needsTranslation {
            guard lastProvisionalText[speaker] != text else { return }
            lastProvisionalText[speaker] = text
            scheduleTranslation(id: sectionID, final: false)
        } else {
            store.setNativeCaption(id: sectionID)
        }
    }

    private func handleCommit(_ recognized: String, speaker: Speaker) {
        guard sessionState != .idle else { return }
        let text = recognized.trimmed
        guard !text.isEmpty else { return }
        let (sectionID, sealedID) = store.appendCommitted(text, speaker: speaker)
        if let sealedID { scheduleTranslation(id: sealedID, final: true) }
        lastProvisionalText[speaker] = nil

        if languagePair.needsTranslation {
            scheduleTranslation(id: sectionID, final: false)
        } else {
            store.setNativeCaption(id: sectionID)
        }
        tickInsights()
    }

    private func sealTurn(_ speaker: Speaker) {
        if let sectionID = store.endTurn(speaker) {
            scheduleTranslation(id: sectionID, final: true)
        }
    }

    private func sealOpenTurn() {
        sealTurn(.remote)
        sealTurn(.mine)
    }

    private func scheduleTranslation(id: Int, final: Bool) {
        guard languagePair.needsTranslation else { return }
        guard let section = store.section(id: id), !section.sourceText.isEmpty else {
            if final { translation.cancel(sectionId: id) }
            return
        }
        let target = section.sourceText
        let context = section.priorContext.joined(separator: " ").trimmed
        let hasContext = !context.isEmpty
        let source = hasContext ? context + " ||| " + target : target
        let generation = store.beginTranslation(id: id)
        translation.enqueue(
            sessionID: sessionID,
            generation: generation,
            sectionId: id,
            source: source,
            target: target,
            isFinal: final,
            hasContext: hasContext
        )
    }

    // MARK: - Persistence and state helpers

    private func beginFreshSession() {
        translation.cancelPending()
        sessionID = UUID()
        activeVocabulary = sourceLanguage == .english
            ? (activeRecord?.effectiveVocabulary(global: globalVocabulary) ?? globalVocabulary) : []
        store.clear()
        lastProvisionalText.removeAll()
        let now = Date()
        sessionStartedAt = now
        meetingStartedAt = now
        pausedElapsed = 0
        sessionState = .starting
        statusMessage = "Starting…"
    }

    func generateInsight(_ configuration: InsightConfiguration, summary: Bool = false) {
        generateInsights(configuration: configuration, summary: summary)
    }

    func generateAllInsights() {
        generateInsights(configuration: nil, summary: false)
    }

    private func generateInsights(configuration: InsightConfiguration?, summary: Bool) {
        guard let record = workspaceRecord, let insights else { return }
        let isLive = selectedHistoryRecord == nil && record.id == activeRecordID
        let sources = isLive
            ? InsightSource.capture(store.sections, includingProvisional: true)
            : InsightSource.capture(record.lines)
        let vocabulary = record.effectiveVocabulary(global: globalVocabulary)
        let duration = isLive ? elapsedSeconds : TimeInterval(record.durationSec)
        if let configuration {
            insights.generate(record: record, configuration: configuration, kind: summary ? .summary : .manual,
                              sources: sources, vocabulary: vocabulary, elapsedSeconds: duration)
        } else {
            insights.generateAll(record: record, sources: sources, vocabulary: vocabulary, elapsedSeconds: duration)
        }
    }

    private func tickInsights() {
        guard sessionState == .recording, selectedHistoryRecord == nil, let record = activeRecord else { return }
        insights?.automaticTick(record: record, sections: store.sections,
                                 vocabulary: record.effectiveVocabulary(global: globalVocabulary),
                                 elapsedSeconds: elapsedSeconds)
    }

    private func freezeElapsedTime() {
        pausedElapsed = elapsedSeconds
        sessionStartedAt = nil
    }

    private func currentEndedAt() -> Date {
        (meetingStartedAt ?? Date()).addingTimeInterval(elapsedSeconds)
    }

    private func startAutosave() {
        if let activeRecord { insights?.startRecording(activeRecord, sections: store.sections) }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                guard let self, self.sessionState == .recording else { continue }
                self.tickInsights()
                do {
                    try self.persistActiveRecord(status: .recording)
                } catch {
                    self.statusMessage = "Autosave failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func persistActiveRecord(status: MeetingStatus) throws {
        guard let record = activeRecord, let history else { return }
        if record.meetingStatus == .draft {
            record.language = languagePair.rawValue
            try history.save()
            return
        }
        try history.sync(
            record: record,
            sections: store.sections,
            endedAt: currentEndedAt(),
            status: status
        )
    }

    private func persistTranslationIfPaused() {
        guard sessionState == .paused else { return }
        do {
            try persistActiveRecord(status: .paused)
        } catch {
            statusMessage = "Could not save translations: \(error.localizedDescription)"
        }
    }

    private func suspendCurrent() async -> Bool {
        switch sessionState {
        case .recording:
            guard await pause() else { return false }
        case .starting, .pausing, .stopping:
            return false
        case .paused:
            do {
                try persistActiveRecord(status: .paused)
            } catch {
                statusMessage = "Could not save the meeting: \(error.localizedDescription)"
                return false
            }
        case .idle:
            return true
        }
        return true
    }

    private func mountPaused(_ record: MeetingRecord) throws {
        try history?.setStatus(record, .paused)
        resetSession(keepingTranscript: false)
        let lines = record.lines.sorted { $0.orderIndex < $1.orderIndex }
        store.restore(sections: lines.map { line in
            (
                id: line.sectionId,
                speaker: Speaker(persistedValue: line.speaker),
                source: line.sourceText,
                target: line.targetText,
                startedAt: line.spokenAt
            )
        })
        sessionID = UUID()
        sourceLanguage = record.languagePair.source
        targetLanguage = record.languagePair.target
        meetingStartedAt = record.startedAt
        pausedElapsed = max(0, record.endedAt.timeIntervalSince(record.startedAt))
        sessionStartedAt = nil
        activeRecord = record
        sessionState = .paused
        statusMessage = "Paused"
    }

    private func persistSelection() {
        if let id = selectedRecordID {
            defaults.set(id.uuidString, forKey: Self.selectedMeetingKey)
        } else {
            defaults.removeObject(forKey: Self.selectedMeetingKey)
        }
    }

    private func mountDraft(_ record: MeetingRecord) {
        resetSession(keepingTranscript: false)
        sourceLanguage = record.languagePair.source
        targetLanguage = record.languagePair.target
        activeRecord = record
    }

    func saveDraftLanguages() {
        guard activeRecord?.meetingStatus == .draft else { return }
        persistNow()
    }

    private func resetSession(keepingTranscript: Bool) {
        if let id = activeRecordID { insights?.cancelMeeting(id) }
        autosaveTask?.cancel()
        autosaveTask = nil
        translation.cancelPending()
        sessionID = UUID()
        activeRecord = nil
        sessionStartedAt = nil
        meetingStartedAt = nil
        pausedElapsed = 0
        sessionState = .idle
        lastProvisionalText.removeAll()
        if !keepingTranscript {
            store.clear()
            statusMessage = ""
        }
    }
}
