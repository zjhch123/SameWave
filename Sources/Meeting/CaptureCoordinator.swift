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
    private var activeVocabulary: [String] = []
    var history: MeetingHistoryStore?
    var insights: InsightEngine?
    var refiner: TranscriptRefiner?

    private var activeRecord: MeetingRecord?
    private var autosaveTask: Task<Void, Never>?
    var activeRecordID: UUID? { activeRecord?.id }
    var languagePair: MeetingLanguagePair {
        MeetingLanguagePair(source: sourceLanguage, target: targetLanguage)
    }

    private var systemCapture: SystemAudioCaptureSCK?
    private var systemSpeech: NativeSpeechEngine?
    private var microphoneCapture: MicrophoneCapture?
    private var microphoneSpeech: NativeSpeechEngine?
    private var isChangingMicrophone = false
    private var lastProvisionalText: [Speaker: String] = [:]

    init(speechVocabularySettings: SpeechVocabularySettings) {
        self.speechVocabularySettings = speechVocabularySettings
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
            self.statusMessage = "翻译暂时失败，已保留原文"
            self.persistTranslationIfPaused()
        }
    }

    // MARK: - Lifecycle

    func startGlobal() async {
        guard sessionState == .idle else { return }
        guard let history else {
            statusMessage = "历史数据库不可用，无法开始会议"
            return
        }

        beginFreshSession()
        let expectedSessionID = sessionID
        do {
            activeRecord = try history.beginRecord(
                startedAt: meetingStartedAt ?? Date(),
                languagePair: languagePair
            )
            try await startSystemPipeline(sessionID: expectedSessionID)
        } catch {
            guard sessionID == expectedSessionID, sessionState == .starting else { return }
            var message = error.localizedDescription
            await tearDownPipelines()
            do {
                try discardEmptyActiveRecord()
            } catch {
                message += "；空记录清理失败：\(error.localizedDescription)"
            }
            resetSession(keepingTranscript: false)
            statusMessage = message
            return
        }

        if captionMyMic {
            do {
                try await startMicrophonePipeline(sessionID: expectedSessionID)
            } catch {
                guard sessionID == expectedSessionID, sessionState == .starting else { return }
                if !(error is CancellationError) {
                    statusMessage = "麦克风不可用，仅记录系统音频：\(error.localizedDescription)"
                }
            }
        }

        guard sessionID == expectedSessionID, sessionState == .starting else { return }
        sessionState = .recording
        if statusMessage == "启动中…" || statusMessage == "模型就绪" {
            statusMessage = "聆听系统音频…"
        }
        startAutosave()
    }

    @discardableResult
    func pause() async -> Bool {
        guard sessionState == .recording else { return false }
        freezeElapsedTime()
        sessionState = .pausing
        statusMessage = "正在暂停…"

        await tearDownPipelines()
        sealOpenTurn()
        lastProvisionalText.removeAll()
        let translationsFinished = await translation.waitUntilIdle(timeout: .seconds(5))

        sessionState = .paused
        do {
            try persistActiveRecord(status: .paused)
            statusMessage = translationsFinished ? "已暂停" : "已暂停，部分译文尚未完成"
            return true
        } catch {
            statusMessage = "已暂停，但保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func resume() async {
        guard sessionState == .paused, let activeRecord else { return }
        activeVocabulary = sourceLanguage == .english ? speechVocabularySettings.phrases : []
        sessionState = .starting
        sessionStartedAt = Date()
        statusMessage = "启动中…"
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
                statusMessage = "恢复失败且无法保存暂停状态：\(error.localizedDescription)"
                return
            }
            statusMessage = "恢复失败：\(error.localizedDescription)"
            return
        }

        if captionMyMic {
            do {
                try await startMicrophonePipeline(sessionID: expectedSessionID)
            } catch {
                guard sessionID == expectedSessionID, sessionState == .starting else { return }
                if !(error is CancellationError) {
                    statusMessage = "麦克风不可用，仅记录系统音频：\(error.localizedDescription)"
                }
            }
        }
        guard sessionID == expectedSessionID, sessionState == .starting else { return }
        sessionState = .recording
        if statusMessage == "启动中…" || statusMessage == "模型就绪" {
            statusMessage = "聆听系统音频…"
        }
        startAutosave()
    }

    @discardableResult
    func stop() async -> MeetingRecord? {
        guard sessionState.hasActiveSession, sessionState != .stopping else { return nil }
        if sessionStartedAt != nil { freezeElapsedTime() }
        sessionState = .stopping
        statusMessage = "正在收尾…"

        await tearDownPipelines()
        sealOpenTurn()
        let translationsFinished = await translation.waitUntilIdle(timeout: .seconds(5))
        let endedAt = currentEndedAt()

        guard let record = activeRecord, let history else {
            resetSession(keepingTranscript: true)
            return nil
        }
        do {
            try history.finish(record, sections: store.sections, endedAt: endedAt)
        } catch {
            sessionState = .paused
            statusMessage = "会议保存失败，可重试结束：\(error.localizedDescription)"
            return nil
        }

        let hasTranscript = record.lineCount > 0
        resetSession(keepingTranscript: true)
        statusMessage = translationsFinished ? "" : "已保存原文，部分译文未完成"
        return hasTranscript ? record : nil
    }

    func startNewMeeting() async {
        guard await suspendCurrent() else { return }
        resetSession(keepingTranscript: false)
    }

    func loadSession(_ record: MeetingRecord) async {
        guard record.meetingStatus != .ended, record.id != activeRecord?.id else { return }
        guard await suspendCurrent() else { return }
        resetSession(keepingTranscript: false)
        do {
            try mountPaused(record)
        } catch {
            statusMessage = "会议恢复失败：\(error.localizedDescription)"
        }
    }

    func recoverUnfinishedSession() {
        guard sessionState == .idle, let history else { return }
        do {
            let records = try history.unfinishedRecords()
            guard let latest = records.first else { return }
            try mountPaused(latest)
            for record in records.dropFirst() where record.meetingStatus != .paused {
                record.status = MeetingStatus.paused.rawValue
            }
            try history.save()
        } catch {
            statusMessage = "未完成会议恢复失败：\(error.localizedDescription)"
        }
    }

    func delete(_ record: MeetingRecord) {
        do {
            try history?.delete(record)
        } catch {
            statusMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func persistNow() {
        do {
            try persistActiveRecord(status: sessionState == .recording ? .recording : .paused)
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
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
                    statusMessage = "麦克风不可用：\(error.localizedDescription)"
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
            statusMessage = "系统音频错误：\(error.localizedDescription)"
        } else {
            statusMessage = "麦克风错误，已停止麦克风字幕：\(error.localizedDescription)"
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
        insights?.noteNewFinalContent(
            sections: store.sections,
            speaker: speaker
        )
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
        activeVocabulary = sourceLanguage == .english ? speechVocabularySettings.phrases : []
        store.clear()
        lastProvisionalText.removeAll()
        insights?.reset()
        let now = Date()
        sessionStartedAt = now
        meetingStartedAt = now
        pausedElapsed = 0
        sessionState = .starting
        statusMessage = "启动中…"
    }

    private func freezeElapsedTime() {
        pausedElapsed = elapsedSeconds
        sessionStartedAt = nil
    }

    private func currentEndedAt() -> Date {
        (meetingStartedAt ?? Date()).addingTimeInterval(elapsedSeconds)
    }

    private func startAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                guard let self, self.sessionState == .recording else { continue }
                do {
                    try self.persistActiveRecord(status: .recording)
                } catch {
                    self.statusMessage = "自动保存失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func persistActiveRecord(status: MeetingStatus) throws {
        guard let record = activeRecord, let history else { return }
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
            statusMessage = "译文保存失败：\(error.localizedDescription)"
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
                statusMessage = "会议保存失败：\(error.localizedDescription)"
                return false
            }
        case .idle:
            return true
        }
        return true
    }

    private func mountPaused(_ record: MeetingRecord) throws {
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
        statusMessage = "已暂停"
        try history?.setStatus(record, .paused)
    }

    private func discardEmptyActiveRecord() throws {
        guard let record = activeRecord else { return }
        try history?.delete(record)
    }

    private func resetSession(keepingTranscript: Bool) {
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
            insights?.reset()
            statusMessage = ""
        }
    }
}
