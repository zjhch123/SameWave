import CoreAudio
import Foundation
import Observation

/// Top-level controller wiring capture → Apple on-device speech → whole-block
/// context translation → captions.
@MainActor
@Observable
final class CaptureCoordinator {
    /// The spoken language of the meeting.
    enum MeetingLanguage: String, CaseIterable, Identifiable {
        case english   // recognize English, translate to Chinese
        case chinese   // recognize Chinese, show as-is (no translation)
        var id: String { rawValue }
        var label: String { self == .english ? "英文（译中）" : "中文（不翻译）" }
        var localeID: String { self == .english ? "en-US" : "zh-CN" }
        var needsTranslation: Bool { self == .english }
    }

    /// Selected meeting language (chosen before starting).
    var meetingLanguage: MeetingLanguage = .english

    let store = CaptionStore()
    let translation = TranslationBridge()

    /// The meeting apps currently producing audio (for the picker).
    private(set) var available: [AudioProcessInfo] = []

    private var capture: ProcessTapCapture?
    private var engine: NativeSpeechEngine?

    /// Sliding context window size (sentences translated together as one block).
    private let contextWindowSize = 6
    /// Monotonic generation so stale block translations can be ignored.
    private var blockGeneration = 0

    /// Provisional (in-progress sentence) translation throttle. We translate the
    /// still-being-spoken sentence for a rough gist, but only every so often and
    /// only when it has grown enough — so a long sentence shows a partial Chinese
    /// preview instead of the user waiting for the speaker to finish.
    private var provisionalGeneration = 0
    private var lastProvisionalText = ""
    private var lastProvisionalAt = Date.distantPast
    private let provisionalMinInterval = 0.7   // seconds between gist translations
    private let provisionalMinGrowth = 8        // chars added since last gist

    init() {
        // Translation arrived; route by kind. Block = the bright refining
        // paragraph; provisional = the dim rough gist of the current sentence.
        translation.onTranslated = { [weak self] generation, kind, chinese in
            guard let self, !chinese.isEmpty else { return }
            switch kind {
            case .block:
                guard generation == self.blockGeneration else { return }
                self.store.setBlockChinese(chinese)
            case .provisional:
                guard generation == self.provisionalGeneration else { return }
                self.store.setInterimChinese(chinese)
            }
        }
    }

    func refreshProcesses() {
        let latest = AudioProcessEnumerator.activeAudioProcesses()
        // Only publish on real change so the 2s auto-refresh doesn't churn the
        // list view (AudioProcessInfo is Hashable with a stable Core Audio id).
        if latest != available { available = latest }
    }

    // MARK: - Start / stop

    /// Caption a specific app (collects Chrome/Electron helper processes too).
    func start(process: AudioProcessInfo) {
        var ids: [AudioObjectID] = [process.id]
        if let known = AudioProcessEnumerator.known.first(where: { process.bundleID.hasPrefix($0.prefix) }) {
            let all = AudioProcessEnumerator.objectIDs(bundlePrefix: known.prefix)
            if !all.isEmpty { ids = all }
        }
        beginCapture(processObjectIDs: ids, statusName: process.name)
    }

    /// Caption ALL system audio (global tap).
    func startGlobal() {
        beginCapture(processObjectIDs: [], statusName: "系统音频")
    }

    private func beginCapture(processObjectIDs ids: [AudioObjectID], statusName: String) {
        guard !store.isRunning else { return }
        store.clear()
        blockGeneration = 0
        store.status = "启动中…"
        store.isRunning = true

        // Recognition is Apple's on-device SpeechAnalyzer for both languages.
        //  - Chinese → shown as-is (no translation)
        //  - English → routed through whole-block context translation
        let isChinese = (meetingLanguage == .chinese)
        let engine = NativeSpeechEngine(
            localeID: meetingLanguage.localeID,
            onInterim: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    if isChinese { self.store.updateInterimChineseNative(text) }
                    else { self.handleInterim(text) }
                }
            },
            onCommit: { [weak self] text in
                Task { @MainActor in self?.handleCommit(text) }
            },
            onStatus: { [weak self] status in
                Task { @MainActor in self?.store.status = status }
            })
        self.engine = engine

        let capture = ProcessTapCapture()
        capture.onAudio = { samples in engine.feed(samples) }
        self.capture = capture

        Task {
            await engine.load()
            do {
                try capture.start(processObjectIDs: ids)
                engine.setInputSampleRate(capture.inputSampleRate)
                store.status = "聆听 \(statusName)…"
            } catch {
                store.status = "捕获失败: \(error)"
                store.isRunning = false
            }
        }
    }

    func stop() {
        capture?.stop()
        capture = nil
        engine?.flush()
        engine = nil
        // Sediment whatever's still in the current block so nothing is lost.
        store.sedimentBlock()
        store.isRunning = false
        store.status = "已停止"
    }

    // MARK: - Result handling

    private func handleInterim(_ english: String) {
        store.updateInterim(english: english)

        // Rough live gist: translate the still-being-spoken sentence so a long
        // sentence shows a partial Chinese preview instead of the user waiting for
        // it to finish. Throttled by time AND growth so we don't spam the pump;
        // the committed block translation always refines it later.
        let text = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 4 else { return }
        let grew = text.count - lastProvisionalText.count >= provisionalMinGrowth
        let elapsed = Date().timeIntervalSince(lastProvisionalAt) >= provisionalMinInterval
        guard grew, elapsed else { return }

        lastProvisionalText = text
        lastProvisionalAt = Date()
        provisionalGeneration += 1
        // Translate just the in-progress sentence on its own — a rough standalone
        // gist. (We can't splice out a context prefix from Apple's translation, so
        // keep it self-contained; the committed block translation refines it later
        // with full context.)
        translation.enqueue(generation: provisionalGeneration, kind: .provisional,
                            english: text)
    }

    private func handleCommit(_ recognized: String) {
        let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // The sentence finalized — retire any in-progress gist state.
        lastProvisionalText = ""
        lastProvisionalAt = .distantPast

        if !meetingLanguage.needsTranslation {
            // Chinese meeting: the recognized text IS the caption — no translation.
            // Show each sentence as its own finalized line.
            store.appendChineseLine(text)
            return
        }

        // If the block is full, sediment it to history before starting the new
        // sentence — so the visible block stays a bounded, refining paragraph.
        if store.block.english.count >= contextWindowSize {
            store.sedimentBlock()
        }

        // Add the new sentence to the current block and re-translate the WHOLE
        // block for maximum context. The whole Chinese paragraph refines in place.
        store.appendToBlock(english: text)
        blockGeneration += 1
        translation.enqueue(generation: blockGeneration, kind: .block,
                            english: store.block.joinedEnglish)
    }
}
