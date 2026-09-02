import Foundation
import Observation

/// Top-level controller wiring capture → Apple on-device speech → the Section
/// state machine → per-section context translation.
///
/// The speech engine emits interim (volatile) + commit (finalized) text per stream.
/// Segmentation follows a **single-floor** rule (see CaptionStore): only one section
/// is open at a time, and a **finalized sentence** seizes the floor — sealing
/// whoever held it. A non-floor speaker's interim partials are ignored, so echo /
/// cross-talk on the idle stream can't thrash the active turn. A continuous
/// same-speaker monologue stays ONE section (its sentences translate together for
/// full paragraph context — that context is what makes translation good), sealing
/// only when the OTHER speaker commits (a real turn switch) or after the section's
/// sliding window fills (`maxSentencesPerSection`). There is deliberately NO
/// time/silence-based sealing: it used to slice a monologue into single-sentence
/// sections that each translated out of context (a quality regression) — a pause is
/// not a turn end.
@MainActor
@Observable
final class CaptureCoordinator {
    /// The spoken language of the meeting.
    enum MeetingLanguage: String, CaseIterable, Identifiable {
        case english   // recognize English, translate to Chinese
        case chinese   // recognize Chinese, show as-is (no translation)
        var id: String { rawValue }
        var label: String {
            switch self {
            case .english:  return "英文（译中）"
            case .chinese:  return "中文（不翻译）"
            }
        }
        /// Compact label for the tight floating dock segmented control.
        var shortLabel: String {
            switch self {
            case .english:  return "英→中"
            case .chinese:  return "中文"
            }
        }
        /// BCP-47 locale for on-device speech recognition (remote/Apple stream).
        var localeID: String {
            switch self {
            case .english:  return "en-US"
            case .chinese:  return "zh-CN"
            }
        }
        /// Source language identifier for the Apple Translation session (nil = no
        /// translation, i.e. Chinese shown as-is).
        var translationSource: String? {
            switch self {
            case .english:  return "en"
            case .chinese:  return nil
            }
        }
        var needsTranslation: Bool { translationSource != nil }
    }

    /// Selected meeting language (chosen before starting).
    var meetingLanguage: MeetingLanguage = .english

    /// Also caption the user's own microphone (my voice). When off, only the remote
    /// (system-audio) stream runs.
    var captionMyMic: Bool = true

    /// When the current capture segment started (reset on resume), for the timer.
    /// `nil` when idle. Elapsed = `pausedElapsed` + (now − this).
    private(set) var sessionStartedAt: Date?
    /// True while the meeting is paused (capture stopped, transcript & state kept).
    private(set) var isPaused: Bool = false
    /// Seconds already elapsed before the current running segment (accumulates across
    /// pause/resume cycles) so the timer freezes on pause and continues on resume.
    private var pausedElapsed: TimeInterval = 0
    /// True wall-clock start of the whole meeting (NOT reset by pause), for history.
    private var meetingStartedAt: Date?
    /// A human-readable status/error line (permission prompts, model download, capture
    /// failures). Surfaced by the empty-state view so setup problems are visible rather
    /// than silent. Empty when there's nothing to report.
    private(set) var statusMessage: String = ""
    /// Total elapsed meeting time, honoring pauses.
    var elapsedSeconds: TimeInterval {
        pausedElapsed + (sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// The single system-audio capture source (SCK grabs all output minus our own —
    /// there is no per-app picker), shown in the "聆听…" status line.
    private static let sourceName = "系统音频"

    let store = CaptionStore()
    let translation = TranslationBridge()

    /// Persistent meeting history (SwiftData). Injected at launch; nil in previews.
    var history: MeetingHistoryStore?
    /// AI meeting-insights engine. Injected at launch (constructed with the user's
    /// InsightSettings); nil in previews / when unconfigured. Fed finalized content from
    /// `handleCommit` and reset per meeting.
    var insights: InsightEngine?
    /// The live record being written this meeting (created on start, synced every few
    /// seconds and on every state change, finalized on stop). nil when idle.
    private var activeRecord: MeetingRecord?
    /// Repeating task that flushes the live transcript to disk while recording, so a
    /// crash/quit loses at most a few seconds. Cancelled on pause/stop.
    private var autosaveTask: Task<Void, Never>?
    /// The id of the live/paused record on disk, so the sidebar can tell which history
    /// row is "the current session" (tap → live view, not detail).
    var activeRecordID: UUID? { activeRecord?.id }

    // Remote stream (system audio → the other participant) via ScreenCaptureKit →
    // Apple SpeechAnalyzer. SCK (not a Core Audio process tap) because opening the
    // mic degraded the tapped output; SCK's audio path is unaffected. SCK captures
    // ALL system audio (excluding our own), so there is no per-app source picker.
    private var capture: SystemAudioCaptureSCK?
    private var engine: NativeSpeechEngine?
    // Mine stream (microphone → my own voice) → Apple SpeechAnalyzer, same as the
    // remote stream. Two Apple engines coexist cleanly under ScreenCaptureKit.
    // Attribution is physical: mic audio only reaches this engine, system audio only
    // the remote one — a result can only carry the speaker of the audio that made it.
    private var micCapture: MicrophoneCapture?
    private var micEngine: NativeSpeechEngine?

    /// Last interim text we enqueued per speaker — used only to skip enqueuing an
    /// exact duplicate (Apple sometimes repeats a volatile hypothesis unchanged).
    /// NOT a throttle: any *changed* interim translates immediately. Rate limiting is
    /// the per-section coalescing mailbox's job, not ours.
    private var lastProvisionalText: [Speaker: String] = [:]

    init() {
        // A translation result arrived. Route it to its section, dropping stale ones
        // by generation. `.isFinal` (the sealed-section translation) drives DONE.
        translation.onTranslated = { [weak self] req, chinese in
            guard let self, !chinese.isEmpty else { return }
            self.store.applyTranslation(chinese, id: req.sectionId,
                                        generation: req.generation, final: req.isFinal)
        }
    }

    // MARK: - Start / stop

    /// Caption ALL system audio (ScreenCaptureKit). One entry point — SCK grabs the
    /// whole system output (minus our own), which is all a 1:1 meeting needs.
    func startGlobal() {
        guard !store.isRunning else { return }
        store.clear()
        lastProvisionalText.removeAll()
        insights?.reset()
        sessionStartedAt = Date()
        pausedElapsed = 0
        isPaused = false
        meetingStartedAt = Date()
        statusMessage = "启动中…"
        store.isRunning = true

        // Open the on-disk record immediately (status "recording") and begin
        // autosaving, so this meeting survives a crash/quit even before "结束".
        activeRecord = history?.beginRecord(startedAt: meetingStartedAt ?? Date(),
                                            language: meetingLanguage.rawValue)
        startAutosave()

        beginRemote()                     // system audio → other party
        if captionMyMic { beginMic() }    // microphone → my own voice
    }

    /// Flush the live transcript to disk every few seconds while recording. Cheap
    /// (UPSERT by section id); the only thing standing between an in-progress meeting
    /// and a crash. Cancelled on pause/stop; a final flush happens there too.
    private func startAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, let rec = self.activeRecord, self.store.isRunning,
                      !self.isPaused else { continue }
                self.history?.sync(record: rec, sections: self.store.sections,
                                   endedAt: self.currentEndedAt())
            }
        }
    }

    /// Meeting end-timestamp for the current elapsed time (used for saved duration).
    private func currentEndedAt() -> Date {
        (meetingStartedAt ?? Date()).addingTimeInterval(elapsedSeconds)
    }

    /// Force an immediate flush of the live transcript — used on app termination so
    /// nothing in the last autosave window is lost.
    func persistNow() {
        guard let rec = activeRecord else { return }
        history?.sync(record: rec, sections: store.sections, endedAt: currentEndedAt())
    }

    /// Tear down both audio streams and their speech engines. Shared by pause / stop /
    /// suspend so the teardown ordering (which matters for the ASR pipeline) lives in
    /// exactly one place.
    private func teardownStreams() {
        autosaveTask?.cancel(); autosaveTask = nil
        capture?.stop();    capture = nil
        micCapture?.stop(); micCapture = nil
        engine?.stop();     engine = nil
        micEngine?.stop();  micEngine = nil
    }

    /// End `speaker`'s turn, scheduling a final translation for whatever it sealed.
    private func sealTurn(_ speaker: Speaker) {
        if let sealed = store.endTurn(speaker) { scheduleTranslation(id: sealed, final: true) }
    }

    /// Seal both speakers' open turns so nothing is left dangling.
    private func sealBothTurns() {
        sealTurn(.remote)
        sealTurn(.mine)
    }

    /// Reset the per-session scalar state to idle. Shared by stop() (which keeps the
    /// transcript on screen) and resetToBlank() (which also clears it).
    private func resetSessionScalars() {
        activeRecord = nil
        sessionStartedAt = nil
        meetingStartedAt = nil
        pausedElapsed = 0
        isPaused = false
        store.isRunning = false
    }

    /// Pause the meeting: stop capture + recognition but KEEP the transcript, section
    /// state, and elapsed time. The timer freezes. Nothing is saved (that's stop()).
    func pause() {
        guard store.isRunning, !isPaused else { return }
        pausedElapsed = elapsedSeconds     // freeze elapsed before dropping the segment
        sessionStartedAt = nil
        teardownStreams()
        sealBothTurns()                    // seal open turns, but do NOT clear or archive
        lastProvisionalText.removeAll()
        isPaused = true
        statusMessage = "已暂停"
        // Persist the paused state: flush the transcript and mark the record "paused"
        // so a quit/relaunch while paused recovers it (rather than losing it).
        if let rec = activeRecord {
            history?.sync(record: rec, sections: store.sections, endedAt: currentEndedAt())
            history?.setStatus(rec, "paused")
        }
    }

    /// Resume a paused meeting: restart capture into the SAME transcript, continuing
    /// the timer. New speech appends to the existing sections.
    func resume() {
        guard store.isRunning, isPaused else { return }
        isPaused = false
        sessionStartedAt = Date()          // new running segment; pausedElapsed holds the rest
        statusMessage = "启动中…"
        if let rec = activeRecord { history?.setStatus(rec, "recording") }
        startAutosave()
        beginRemote()
        if captionMyMic { beginMic() }
    }

    /// Build a NativeSpeechEngine that routes results to `speaker`.
    private func makeEngine(for speaker: Speaker) -> NativeSpeechEngine {
        return NativeSpeechEngine(
            localeID: meetingLanguage.localeID,
            onInterim: { [weak self] text in
                Task { @MainActor in self?.handleInterim(text, speaker: speaker) }
            },
            onCommit: { [weak self] text in
                Task { @MainActor in self?.handleCommit(text, speaker: speaker) }
            },
            onStatus: { [weak self] status in
                // Only the remote stream drives the visible status line.
                Task { @MainActor in if speaker == .remote { self?.statusMessage = status } }
            })
    }

    private func beginRemote() {
        let engine = makeEngine(for: .remote)
        self.engine = engine
        let capture = SystemAudioCaptureSCK()
        capture.onAudio = { samples in engine.feed(samples) }
        capture.onError = { [weak self] err in
            Task { @MainActor in self?.statusMessage = "系统音频错误: \(err.localizedDescription)" }
        }
        self.capture = capture

        Task {
            await engine.load()
            do {
                try await capture.start()
                engine.setInputSampleRate(capture.inputSampleRate)
                statusMessage = "聆听 \(Self.sourceName)…"
            } catch {
                statusMessage = "捕获失败: \(error.localizedDescription)"
                store.isRunning = false
            }
        }
    }

    /// Start captioning my own microphone with a second Apple SpeechAnalyzer. Under
    /// ScreenCaptureKit capture (not the old process tap), two Apple engines coexist
    /// cleanly — the earlier garbling was the process tap being degraded when the mic
    /// opened, NOT engine contention. Attribution stays physically perfect: mic audio
    /// only ever reaches this engine, system audio only the remote one.
    private func beginMic() {
        let engine = makeEngine(for: .mine)
        self.micEngine = engine
        let capture = MicrophoneCapture()
        capture.onAudio = { samples in engine.feed(samples) }
        self.micCapture = capture
        Task {
            await engine.load()
            do {
                try await capture.start()
                engine.setInputSampleRate(capture.inputSampleRate)
            } catch {
                statusMessage = "麦克风不可用: \(error)"
            }
        }
    }

    /// Tear down just the mic stream, ending my turn (sealing my open section) so it
    /// isn't left dangling. Leaves the remote stream untouched.
    private func stopMic() {
        micCapture?.stop(); micCapture = nil
        micEngine?.stop();  micEngine = nil
        sealTurn(.mine)
    }

    /// Toggle captioning my own microphone, before OR during a session.
    func setCaptionMyMic(_ on: Bool) {
        guard on != captionMyMic else { return }
        captionMyMic = on
        guard store.isRunning else { return }
        if on {
            if micCapture == nil { beginMic() }
        } else {
            stopMic()
        }
    }

    /// End the meeting and finalize it into history. Returns the just-ended record so
    /// the UI can keep it SELECTED in the sidebar (showing its read-only detail) rather
    /// than dropping back to a blank live view. nil if nothing was recorded.
    @discardableResult
    func stop() -> MeetingRecord? {
        teardownStreams()
        sealBothTurns()
        // Finalize the on-disk record. It already exists and has been synced all along;
        // wait a beat for the last translations to land, then flush + mark "ended".
        let endedAt = currentEndedAt()
        let rec = activeRecord
        let snapshotSections = { [weak self] in self?.store.sections ?? [] }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            if let rec { self?.history?.finish(rec, sections: snapshotSections(), endedAt: endedAt) }
        }
        resetSessionScalars()   // keeps the transcript on screen (no store.clear())
        statusMessage = ""
        return rec
    }

    /// Detach the currently-mounted session WITHOUT ending it, so another can be
    /// mounted. Multiple paused meetings coexist on disk; only ONE is loaded into the
    /// store at a time. If the current one is actively recording it's paused first
    /// (capture torn down, turns sealed, flushed + marked "paused" on disk); if it's
    /// already paused it's just re-flushed. Either way its full transcript stays on
    /// disk as a resumable "paused" record — nothing is lost, nothing is archived.
    /// No-op if nothing is mounted.
    private func suspendCurrent() {
        guard store.isRunning else { return }
        if !isPaused {
            pause()   // tears down capture, seals, flushes, marks "paused" on disk
        } else if let rec = activeRecord {
            history?.sync(record: rec, sections: store.sections, endedAt: currentEndedAt())
            history?.setStatus(rec, "paused")
        }
        // Detach in-memory; the record remains "paused" on disk, fully resumable.
        resetToBlank()
    }

    /// Start a brand-new meeting from the sidebar's "开启新会议". Any mounted session
    /// is SUSPENDED — kept on disk as a resumable paused meeting, not ended — then the
    /// stage is ALWAYS cleared to blank. The unconditional clear matters: after 结束
    /// (stop), the ended transcript lingers in the live view while nothing is running,
    /// so suspendCurrent()'s "nothing to suspend" early-return would otherwise leave
    /// that stale text on screen. Only reachable when idle / paused / stopped (the
    /// button is disabled while actively recording). Lossless; no confirmation needed.
    func startNewMeeting() {
        suspendCurrent()          // suspends & blanks IF a session is mounted…
        resetToBlank()            // …and this guarantees a blank stage regardless
    }

    /// Reset all live/session state to a truly blank, idle stage. Idempotent — safe to
    /// call whether or not `suspendCurrent()` already ran.
    private func resetToBlank() {
        teardownStreams()
        resetSessionScalars()
        store.clear()
        lastProvisionalText.removeAll()
        insights?.reset()
        statusMessage = ""
    }

    /// Switch to a paused/unfinished meeting from the sidebar: suspend whatever's
    /// mounted, then load `record` into the store as a resumable paused session (hit ▶
    /// to continue). No-op if it's already mounted or if it's an ended meeting (those
    /// open in the read-only detail view instead).
    func loadSession(_ record: MeetingRecord) {
        guard record.status != "ended" else { return }
        guard record.id != activeRecord?.id else { return }
        suspendCurrent()
        mountPaused(record)
    }

    /// Rebuild a paused/unfinished `record` into the store as the mounted, resumable
    /// session (shared by crash recovery and sidebar session-switching). The transcript
    /// comes back sealed+done, the timer is restored, and it's marked paused — the user
    /// hits ▶ (resume) to continue recording into it.
    private func mountPaused(_ record: MeetingRecord) {
        let lines = record.lines.sorted { $0.orderIndex < $1.orderIndex }
        let restored = lines.map { l in
            (id: l.sectionId,
             speaker: l.isMine ? Speaker.mine : .remote,
             source: l.sourceText, target: l.targetText, startedAt: l.spokenAt)
        }
        store.restore(sections: restored)
        meetingLanguage = MeetingLanguage(rawValue: record.language) ?? .english
        meetingStartedAt = record.startedAt
        pausedElapsed = record.endedAt.timeIntervalSince(record.startedAt)
        sessionStartedAt = nil
        isPaused = true
        activeRecord = record
        history?.setStatus(record, "paused")   // normalize (may have been "recording")
        store.isRunning = true
        statusMessage = "已暂停"
    }

    // MARK: - Crash / quit recovery

    /// On launch, look for meetings that never reached "ended" (interrupted by a quit
    /// or crash — recording or paused) and mount the NEWEST as a paused, resumable
    /// session (hit ▶ to continue). Any OLDER unfinished meetings stay "paused" on disk
    /// too — they remain in the sidebar as separate resumable sessions (multiple paused
    /// meetings coexist), not force-archived.
    func recoverUnfinishedSession() {
        guard !store.isRunning, let history else { return }
        let orphans = history.unfinishedRecords()
        guard let latest = orphans.first else { return }
        mountPaused(latest)
        // Normalize any older orphans to "paused" (a crash may have left them
        // "recording") so they show the right status — but keep them resumable.
        for old in orphans.dropFirst() where old.status != "paused" {
            old.status = "paused"
        }
        try? history.context.save()
    }

    // MARK: - ASR → speech events → state machine

    private func handleInterim(_ text: String, speaker: Speaker) {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        // A volatile hypothesis. It only touches the section if this speaker holds
        // (or grabs the idle) floor; while the OTHER speaker is mid-turn it's ignored
        // so echo/partial cross-talk can't seize the floor — only a committed
        // sentence can (in handleCommit).
        let (sectionId, sealed) = store.updateInterim(t, speaker: speaker)
        if let sealed { scheduleTranslation(id: sealed, final: true) }
        guard let id = sectionId else { return }   // ignored (other holds floor)

        if !meetingLanguage.needsTranslation {
            store.setNativeCaption(id: id)
            return
        }
        // Eager, un-throttled: translate the growing sentence AS IT COMES — show and
        // translate whatever we have so far, even mid-sentence. No waiting to "batch
        // up a whole sentence"; a rough mid-state translation now beats a perfect one
        // 15s late. The sliding window fixes quality: when the next sentence arrives,
        // the whole section re-translates WITH context, so the earlier rough gist is
        // superseded by a good one. The per-section coalescing mailbox
        // (TranslationBridge) is the ONLY rate limiter — the translator always works
        // on this section's LATEST text and drops superseded snapshots, so enqueuing
        // on every frame can't pile up. (Flicker is handled by the non-animated
        // scroll, so a brisk cadence is safe.) Skip only exact-duplicate text.
        guard t != lastProvisionalText[speaker] else { return }
        lastProvisionalText[speaker] = t
        scheduleTranslation(id: id, final: false)
    }

    private func handleCommit(_ recognized: String, speaker: Speaker) {
        let text = recognized.trimmed
        guard !text.isEmpty else { return }
        // A finalized sentence — this always seizes the floor (sealing the other
        // speaker if they held it), guaranteeing the section list stays in the order
        // sentences were actually produced.
        let (id, sealed) = store.appendCommitted(text, speaker: speaker)
        if let sealed { scheduleTranslation(id: sealed, final: true) }
        // Sentence finalized → clear the interim dedup so the next sentence's first
        // interim always enqueues.
        lastProvisionalText[speaker] = nil

        if !meetingLanguage.needsTranslation {
            store.setNativeCaption(id: id)
        } else {
            scheduleTranslation(id: id, final: false)
        }

        // Feed the insight engine finalized content (it decides when to regenerate,
        // coalescing internally). Passing the committing speaker lets it detect a
        // speaker switch as a natural insight boundary.
        insights?.noteNewFinalContent(sections: store.sections,
                                      language: meetingLanguage, speaker: speaker)
    }

    /// Enqueue a translation for a section's current source. `final` marks the
    /// sealed-section pass whose completion drives the section to DONE. No-op in
    /// Chinese (no-translation) mode.
    ///
    /// The section's frozen `priorContext` (its speaker's preceding sentences) is
    /// prepended as `context ||| target` so the section's first sentence still
    /// translates in-context — the sliding context window is sentence-scoped and
    /// survives the display split. The pump splits the result back to the target. When
    /// there's no context (first section of a speaker) the input is just the target, so
    /// the common cold-start path is byte-identical to the context-free behavior.
    private func scheduleTranslation(id: Int, final: Bool) {
        guard meetingLanguage.needsTranslation else { return }
        guard let sec = store.section(id: id), !sec.sourceText.isEmpty else {
            if final { translation.cancel(sectionId: id) }   // nothing to finalize
            return
        }
        let target = sec.sourceText
        let context = sec.priorContext.joined(separator: " ").trimmed
        let hasContext = !context.isEmpty
        let source = hasContext ? context + " ||| " + target : target

        let gen = store.beginTranslation(id: id)
        translation.enqueue(generation: gen, sectionId: id, source: source,
                            target: target, isFinal: final, hasContext: hasContext)
    }
}
