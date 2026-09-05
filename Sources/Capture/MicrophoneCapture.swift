import AVFoundation
import Foundation

/// Captures the user's own voice from the current default input device through
/// `AVAudioEngine`, emitting mono samples together with the format's sample rate.
///
/// `inputNode` automatically follows the system's selected input device
/// (built-in mic, wired, or Bluetooth headset) — the user just picks it in
/// System Settings. Device changes mid-session (e.g. Bluetooth disconnects,
/// headphones plugged in) fire `.AVAudioEngineConfigurationChange`, on which we
/// rebuild the tap against the new format.
@MainActor
final class MicrophoneCapture {

    enum CaptureError: LocalizedError {
        case notAuthorized
        case engineStart(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Allow SameWave in System Settings › Privacy & Security › Microphone"
            case .engineStart(let error):
                "Could not start the microphone: \(error.localizedDescription)"
            }
        }
    }

    /// Mono Float samples and their device sample rate. Called on an audio thread.
    var onAudio: (@Sendable ([Float], Double) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

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

        // Remove any prior tap (rebuild path) before installing a fresh one.
        input.removeTap(onBus: 0)
        let audioSink = onAudio
        let sampleRate = format.sampleRate
        let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            audioSink?(Self.monoSamples(from: buffer), sampleRate)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: tap)

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
            Task { @MainActor in self?.rebuildForDeviceChange() }
        }
    }

    /// The input device changed (Bluetooth dropped, cable plugged in, …). The
    /// engine has already stopped internally; reset and re-install against the
    /// new device's format, keeping the same `onAudio` consumer.
    private func rebuildForDeviceChange() {
        guard running else { return }
        engine.stop()
        engine.reset()
        do {
            try installTapAndStart()
        } catch {
            running = false
            onError?(error)
        }
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

    // MARK: - Helpers

    /// Downmix an interleaved/planar buffer to a mono `[Float]`.
    nonisolated private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
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

    nonisolated private static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
