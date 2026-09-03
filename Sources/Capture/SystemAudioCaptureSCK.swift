import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures other participants' system audio through ScreenCaptureKit. The stream
/// emits 16 kHz mono samples and excludes this process to avoid self-capture.
@available(macOS 13.0, *)
@MainActor
final class SystemAudioCaptureSCK: NSObject, SCStreamDelegate, SCStreamOutput {

    enum CaptureError: Error, LocalizedError {
        case permissionDenied
        case noDisplayFound
        case captureStartFailed(Error)
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "需要「屏幕录制」权限：系统设置 › 隐私与安全性 › 屏幕录制，勾选 同频"
            case .noDisplayFound:   return "找不到可捕获的显示器"
            case .captureStartFailed(let e): return "系统音频捕获启动失败：\(e.localizedDescription)"
            }
        }
    }

    /// Mono Float samples at `inputSampleRate`. Called on an audio queue.
    nonisolated let onAudio: @Sendable ([Float], Double) -> Void
    nonisolated let onError: @Sendable (Error) -> Void

    /// SCK is configured to deliver this rate directly.
    private let inputSampleRate: Double = 16_000

    /// Bundle-id prefixes to EXCLUDE from capture, or nil to capture all system
    /// audio. (Per-app capture = exclude everything except the target; here we do the
    /// common "all system audio" and just drop our own process.)
    private let excludeBundlePrefixes: [String]

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.plus.meetingcaptions.sck.audio", qos: .userInitiated)

    init(excludeBundlePrefixes: [String] = [],
         onAudio: @escaping @Sendable ([Float], Double) -> Void,
         onError: @escaping @Sendable (Error) -> Void) {
        self.excludeBundlePrefixes = excludeBundlePrefixes
        self.onAudio = onAudio
        self.onError = onError
    }

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first else { throw CaptureError.noDisplayFound }

        // Exclude our own app (never capture our own output) plus any requested apps.
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.plus.meetingcaptions"
        let excluded = content.applications.filter { app in
            app.bundleIdentifier == ownBundle
                || excludeBundlePrefixes.contains { app.bundleIdentifier.hasPrefix($0) }
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(inputSampleRate)   // 16 kHz — analyzer-ready
        config.channelCount = 1
        config.queueDepth = 8
        // Minimal video (SCK requires a display capture even for audio-only).
        config.width = 2
        config.height = 2

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        do {
            try await s.startCapture()
        } catch {
            // Permission was already validated by the content query above, so a failure
            // here is a real capture-start problem (config/filter/display) — preserve it
            // rather than mislabeling it a permission issue.
            throw CaptureError.captureStartFailed(error)
        }
        self.stream = s
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            onError(error)
        }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                           of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        guard let chunk = Self.monoFloat(from: sampleBuffer) else { return }
        if !chunk.samples.isEmpty { onAudio(chunk.samples, chunk.sampleRate) }
    }

    // MARK: - CMSampleBuffer → [Float] mono

    /// Extract mono Float32 samples from an SCK audio CMSampleBuffer. SCK delivers
    /// PCM Float32; with channelCount=1 it's already mono, but we defensively
    /// downmix if more channels ever arrive.
    nonisolated private static func monoFloat(
        from sb: CMSampleBuffer
    ) -> (samples: [Float], sampleRate: Double)? {
        guard let fmt = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee else { return nil }
        let frames = CMSampleBufferGetNumSamples(sb)
        guard frames > 0 else { return nil }
        let channels = Int(asbd.mChannelsPerFrame)

        // Copy the audio into an AudioBufferList backed by our own memory.
        var blockBuffer: CMBlockBuffer?
        let listSize = MemoryLayout<AudioBufferList>.size + (channels - 1) * MemoryLayout<AudioBuffer>.size
        let ablPtr = UnsafeMutableRawPointer.allocate(byteCount: max(listSize, MemoryLayout<AudioBufferList>.size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ablPtr.deallocate() }
        let abl = ablPtr.assumingMemoryBound(to: AudioBufferList.self)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: abl,
            bufferListSize: max(listSize, MemoryLayout<AudioBufferList>.size),
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        guard isFloat else { return nil }   // SCK is Float32

        if buffers.count == 1 {
            let b = buffers[0]
            guard let data = b.mData else { return nil }
            let ch = Int(b.mNumberChannels)
            let ptr = data.assumingMemoryBound(to: Float.self)
            let total = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            if ch <= 1 {
                return (Array(UnsafeBufferPointer(start: ptr, count: total)), asbd.mSampleRate)
            }
            // Interleaved multi-channel → average to mono.
            let n = total / ch
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                var acc: Float = 0
                for c in 0..<ch { acc += ptr[i * ch + c] }
                out[i] = acc / Float(ch)
            }
            return (out, asbd.mSampleRate)
        } else {
            // Planar: one buffer per channel → average.
            let n = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
            var out = [Float](repeating: 0, count: n)
            var used = 0
            for b in buffers {
                guard let data = b.mData else { continue }
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<n { out[i] += p[i] }
                used += 1
            }
            if used > 1 { for i in 0..<n { out[i] /= Float(used) } }
            return (out, asbd.mSampleRate)
        }
    }
}
