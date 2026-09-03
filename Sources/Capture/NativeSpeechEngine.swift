import AppKit
import AVFoundation
import Foundation
import Speech
import Synchronization

/// Actor-isolated Apple Speech pipeline shared by the system-audio and microphone
/// paths. Audio callbacks write to a bounded AsyncStream, keeping AVAudioConverter
/// and SpeechAnalyzer state on one executor without unsafe Sendable declarations.
@available(macOS 26.0, *)
actor NativeSpeechEngine {
    private static let experimentalContextualStrings = [
        "claude code",
        "Bestla",
        "ODB",
        "FileItem",
        "bootstrap",
        "Arbutus",
        "XPay",
        "Wallet",
        "Copilot",
        "M365 Copilot",
        "One Copilot",
        "OneCopilotMobile",
        "OCM",
        "Unified Copilot",
        "Unified App Experience",
        "ExP",
        "Scorecard",
        "ECS",
        "ADO",
        "Kusto",
        "Intune",
        "Entra",
        "GlobalProtect",
        "PR",
        "SKU",
        "AAD",
        "MSAL",
        "OBO",
        "UPN",
        "1JS",
        "SSR",
        "SSE",
        "SAW",
        "RAI",
        "CELA",
        "MSAI",
        "Yujie Liu",
        "Shixin Cai",
        "Jessica Zhang",
        "Baogui Yan",
        "Lei Bian",
    ]

    private struct AudioChunk: Sendable {
        let samples: [Float]
        let sampleRate: Double
    }

    enum EngineError: LocalizedError {
        case notAuthorized
        case assetInstallation(Error)
        case customLanguageModel(Error)
        case noCompatibleAudioFormat
        case analyzerStart(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "需要在「系统设置 › 隐私与安全性 › 语音识别」中允许同频"
            case .assetInstallation(let error):
                "语音模型准备失败：\(error.localizedDescription)"
            case .customLanguageModel(let error):
                "词表模型准备失败：\(error.localizedDescription)"
            case .noCompatibleAudioFormat:
                "语音识别器没有可用的音频格式"
            case .analyzerStart(let error):
                "语音识别启动失败：\(error.localizedDescription)"
            }
        }
    }

    private let localeID: String
    private let onInterim: @Sendable (String) async -> Void
    private let onCommit: @Sendable (String) async -> Void
    private let onStatus: @Sendable (String) async -> Void

    private var speechTranscriber: SpeechTranscriber?
    private var dictationTranscriber: DictationTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?

    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    nonisolated let feed: @Sendable ([Float], Double) -> Void
    private let audioSamples: AsyncStream<AudioChunk>
    private let audioContinuation: AsyncStream<AudioChunk>.Continuation

    init(localeID: String,
         onInterim: @escaping @Sendable (String) async -> Void,
         onCommit: @escaping @Sendable (String) async -> Void,
         onStatus: @escaping @Sendable (String) async -> Void) {
        let pair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(64))
        audioSamples = pair.stream
        audioContinuation = pair.continuation
        feed = { samples, sampleRate in
            guard !samples.isEmpty, sampleRate > 0 else { return }
            pair.continuation.yield(AudioChunk(samples: samples, sampleRate: sampleRate))
        }
        self.localeID = localeID
        self.onInterim = onInterim
        self.onCommit = onCommit
        self.onStatus = onStatus
    }

    func load() async throws {
        await onStatus("请求语音识别权限…")
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
        guard await Self.requestAuthorization() else { throw EngineError.notAuthorized }

        let locale = Locale(identifier: localeID)
        let modules: [any SpeechModule]
        if localeID == "en-US" {
            await onStatus("准备词表模型…")
            let modelConfiguration: SFSpeechLanguageModel.Configuration
            do {
                modelConfiguration = try await CustomSpeechLanguageModel.shared.configuration(
                    locale: locale,
                    phrases: Self.experimentalContextualStrings
                )
            } catch {
                throw EngineError.customLanguageModel(error)
            }

            var preset = DictationTranscriber.Preset.progressiveLongDictation
            preset.contentHints.insert(
                .customizedLanguage(modelConfiguration: modelConfiguration)
            )
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: preset.contentHints,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions,
                attributeOptions: preset.attributeOptions
            )
            dictationTranscriber = transcriber
            modules = [transcriber]
        } else {
            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: .progressiveTranscription
            )
            speechTranscriber = transcriber
            modules = [transcriber]
        }

        do {
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: modules
            ) {
                await onStatus("首次使用，下载语音模型…")
                try await request.downloadAndInstall()
            }
        } catch {
            throw EngineError.assetInstallation(error)
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else {
            throw EngineError.noCompatibleAudioFormat
        }
        analyzerFormat = format

        let analysisContext = AnalysisContext()
        analysisContext.contextualStrings[.general] = Self.experimentalContextualStrings

        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        let inputPair = AsyncStream<AnalyzerInput>.makeStream()
        analyzerInput = inputPair.continuation
        if let dictationTranscriber {
            startResultsDrain(transcriber: dictationTranscriber)
        } else if let speechTranscriber {
            startResultsDrain(transcriber: speechTranscriber)
        }
        startAudioDrain()

        do {
            try await analyzer.setContext(analysisContext)
            try await analyzer.start(inputSequence: inputPair.stream)
            await onStatus("模型就绪")
        } catch {
            throw EngineError.analyzerStart(error)
        }
    }

    /// Stops accepting audio, converts every sample already queued, then asks Speech
    /// to finalize before waiting for the result stream. This preserves the last final
    /// utterance instead of cancelling the consumer while finalization is still running.
    func stop() async {
        audioContinuation.finish()
        await audioTask?.value
        audioTask = nil

        analyzerInput?.finish()
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                resultsTask?.cancel()
                await onStatus("识别收尾失败：\(error.localizedDescription)")
            }
        }
        await resultsTask?.value
        resultsTask = nil

        analyzer = nil
        speechTranscriber = nil
        dictationTranscriber = nil
        analyzerInput = nil
        analyzerFormat = nil
        sourceFormat = nil
        converter = nil
    }

    private func startResultsDrain(transcriber: SpeechTranscriber) {
        let onInterim = onInterim
        let onCommit = onCommit
        let onStatus = onStatus
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmed
                    guard !text.isEmpty else { continue }
                    if result.isFinal {
                        await onCommit(text)
                    } else {
                        await onInterim(text)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await onStatus("识别错误：\(error.localizedDescription)")
            }
        }
    }

    private func startResultsDrain(transcriber: DictationTranscriber) {
        let onInterim = onInterim
        let onCommit = onCommit
        let onStatus = onStatus
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmed
                    guard !text.isEmpty else { continue }
                    if result.isFinal {
                        await onCommit(text)
                    } else {
                        await onInterim(text)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await onStatus("识别错误：\(error.localizedDescription)")
            }
        }
    }

    private func startAudioDrain() {
        audioTask = Task {
            for await chunk in audioSamples {
                await convertAndYield(chunk)
            }
        }
    }

    private func convertAndYield(_ chunk: AudioChunk) async {
        let samples = chunk.samples
        let inputSampleRate = chunk.sampleRate
        guard let analyzerFormat, let analyzerInput, !samples.isEmpty else { return }

        if sourceFormat?.sampleRate != inputSampleRate {
            sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputSampleRate,
                channels: 1,
                interleaved: false
            )
            if let sourceFormat {
                converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat)
            }
        }
        guard let sourceFormat, let converter,
              let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
              ) else { return }

        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress,
                  let channel = inputBuffer.floatChannelData?[0] else { return }
            channel.update(from: baseAddress, count: samples.count)
        }

        let ratio = analyzerFormat.sampleRate / inputSampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 1_024
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: capacity
        ) else { return }

        let pendingInput = Mutex<AVAudioPCMBuffer?>(inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            pendingInput.withLock { inputBuffer in
                guard let buffer = inputBuffer else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputBuffer = nil
                inputStatus.pointee = .haveData
                return buffer
            }
        }
        if status == .error {
            let detail = conversionError?.localizedDescription ?? "未知错误"
            await onStatus("音频格式转换失败：\(detail)")
            return
        }
        guard outputBuffer.frameLength > 0 else { return }
        analyzerInput.yield(AnalyzerInput(buffer: outputBuffer))
    }

    nonisolated static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
