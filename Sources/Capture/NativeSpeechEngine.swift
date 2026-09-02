import AppKit
import AVFoundation
import Foundation
import Speech

/// On-device speech recognition using Apple's native SpeechAnalyzer (macOS 26+).
///
/// Used for both Chinese and English. The model is Apple's system-shared asset —
/// no app-bundled model, no size cost; the locale's asset is fetched once from
/// Apple on first use then runs fully offline.
///
/// We feed the tap's mono Float samples (at the input sample rate) and convert to
/// the analyzer's preferred format. Results stream as volatile (interim) and
/// finalized (commit) via the onInterim / onCommit / onStatus callbacks.
@available(macOS 26.0, *)
final class NativeSpeechEngine: @unchecked Sendable {

    private let localeID: String
    private let onInterim: @Sendable (String) -> Void
    private let onCommit: @Sendable (String) -> Void
    private let onStatus: @Sendable (String) -> Void

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    /// Source format of samples we're fed (mono Float32 at the tap rate).
    private nonisolated(unsafe) var inputSampleRate = 48_000.0
    func setInputSampleRate(_ sr: Double) { inputSampleRate = sr }
    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(localeID: String,
         onInterim: @escaping @Sendable (String) -> Void,
         onCommit: @escaping @Sendable (String) -> Void,
         onStatus: @escaping @Sendable (String) -> Void) {
        self.localeID = localeID
        self.onInterim = onInterim
        self.onCommit = onCommit
        self.onStatus = onStatus
    }

    /// Request permission, ensure the locale asset is installed, and start.
    func load() async {
        onStatus("请求语音识别权限…")
        // Bring the app forward so the system permission prompt is visible.
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
        let authorized = await Self.requestAuthorization()
        guard authorized else {
            onStatus("需要在「系统设置 › 隐私与安全性 › 语音识别」中允许 MeetingCaptions")
            return
        }

        let locale = Locale(identifier: localeID)
        // .progressiveTranscription is Apple's live-caption preset: streaming
        // volatile (partial) + finalized results, auto punctuation.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber

        // Ensure the system model asset for this locale is installed.
        do {
            let installed = await SpeechTranscriber.installedLocales
            let have = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
            if !have {
                onStatus("首次使用，下载语音模型…")
                if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await req.downloadAndInstall()
                }
            }
        } catch {
            onStatus("语音模型下载失败: \(error.localizedDescription)")
            return
        }

        // Query the analyzer's preferred audio format (only valid after install).
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder

        startResultsDrain()

        do {
            try await analyzer.start(inputSequence: inputSequence)
            onStatus("模型就绪")
        } catch {
            onStatus("识别启动失败: \(error.localizedDescription)")
        }
    }

    /// Drain the transcriber's result stream: volatile → onInterim, finalized →
    /// onCommit. Runs until the input stream ends or the task is cancelled (stop()).
    private func startResultsDrain() {
        resultsTask = Task { [weak self] in
            guard let self, let transcriber = self.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmed
                    guard !text.isEmpty else { continue }
                    if result.isFinal {
                        self.onCommit(text)
                    } else {
                        self.onInterim(text)
                    }
                }
            } catch {
                self.onStatus("识别错误: \(error.localizedDescription)")
            }
        }
    }

    /// Feed mono Float32 samples at the tap's input rate. Safe from any thread.
    func feed(_ samples: [Float]) {
        guard let analyzerFormat, let inputBuilder, !samples.isEmpty else { return }

        // Build a source buffer at the input rate.
        if sourceFormat == nil {
            sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: inputSampleRate,
                                         channels: 1, interleaved: false)
            if let sf = sourceFormat {
                converter = AVAudioConverter(from: sf, to: analyzerFormat)
            }
        }
        guard let sourceFormat, let converter,
              let inBuf = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                           frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            inBuf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        let ratio = analyzerFormat.sampleRate / inputSampleRate
        let cap = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: cap) else { return }

        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil, out.frameLength > 0 else { return }
        inputBuilder.yield(AnalyzerInput(buffer: out))
    }

    /// Stop the engine: finish the input stream, finalize any pending audio, cancel
    /// the results task, and release the analyzer/transcriber. The engine is dead
    /// afterward — a fresh instance is built for the next session.
    func stop() {
        inputBuilder?.finish()
        let a = self.analyzer
        Task { try? await a?.finalizeAndFinishThroughEndOfInput() }
        resultsTask?.cancel()
        resultsTask = nil
        self.analyzer = nil
        self.transcriber = nil
        inputBuilder = nil
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}
