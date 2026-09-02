import AVFoundation
import Foundation

/// Captures the user's OWN voice from the current default input device
/// (microphone) via `AVAudioEngine`. Mirrors `ProcessTapCapture`'s interface so
/// the coordinator can feed either source into a `NativeSpeechEngine`
/// interchangeably: same `onAudio: (([Float]) -> Void)?` mono callback at
/// `inputSampleRate`, same `start()`/`stop()` lifecycle.
///
/// `inputNode` automatically follows the system's selected input device
/// (built-in mic, wired, or Bluetooth headset) — the user just picks it in
/// System Settings. Device changes mid-session (e.g. Bluetooth disconnects,
/// headphones plugged in) fire `.AVAudioEngineConfigurationChange`, on which we
/// rebuild the tap — analogous to `ProcessTapCapture.rebuildForDeviceChange`.
final class MicrophoneCapture: @unchecked Sendable {

    enum CaptureError: Error {
        case notAuthorized
        case engineStart(Error)
    }

    /// Mono Float samples at `inputSampleRate` (NOT resampled — the engine
    /// resamples whole utterances at once). Called on an audio thread.
    var onAudio: (([Float]) -> Void)?

    /// The input device's native sample rate. Valid after `start`.
    private(set) var inputSampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?
    private var running = false

    // MARK: - Lifecycle

    /// Ensure mic permission, then install a tap and start the engine.
    func start() async throws {
        let authorized = await Self.requestMicAccess()
        guard authorized else { throw CaptureError.notAuthorized }
        try installTapAndStart()
        registerConfigChangeListener()
        running = true
    }

    private func installTapAndStart() throws {
        let input = engine.inputNode

        let format = input.outputFormat(forBus: 0)   // device's native format
        inputSampleRate = format.sampleRate

        // Remove any prior tap (rebuild path) before installing a fresh one.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.onAudio?(Self.monoSamples(from: buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw CaptureError.engineStart(error)
        }
    }

    // MARK: - Device change → rebuild (seamless)

    private func registerConfigChangeListener() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.rebuildForDeviceChange()
        }
    }

    /// The input device changed (Bluetooth dropped, cable plugged in, …). The
    /// engine has already stopped internally; reset and re-install against the
    /// new device's format, keeping the same `onAudio` consumer.
    private func rebuildForDeviceChange() {
        guard running else { return }
        engine.stop()
        engine.reset()
        try? installTapAndStart()
    }

    func stop() {
        running = false
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    deinit { stop() }

    // MARK: - Helpers

    /// Downmix an interleaved/planar buffer to a mono `[Float]`.
    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let channelData = buffer.floatChannelData else { return [] }
        let channels = Int(buffer.format.channelCount)
        if channels <= 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        }
        // Average across channels for a clean mono downmix.
        var out = [Float](repeating: 0, count: frames)
        for ch in 0..<channels {
            let p = channelData[ch]
            for i in 0..<frames { out[i] += p[i] }
        }
        let scale = 1.0 / Float(channels)
        for i in 0..<frames { out[i] *= scale }
        return out
    }

    private static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
