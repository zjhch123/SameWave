import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Captures a specific process's audio OUTPUT via a Core Audio process tap
/// (macOS 14.4+), WITHOUT a virtual driver, while the OS keeps playing to the
/// user's headphones (muteBehavior = .unmuted).
///
/// Pipeline: process tap → private aggregate device → IOProc (realtime) writes
/// raw Float into a ring → a consumer downmixes to mono and hands [Float] windows
/// (at the tap's native sample rate) to the caller via `onAudio`. Resampling to
/// the recognizer's preferred rate happens downstream in `NativeSpeechEngine`.
final class ProcessTapCapture: @unchecked Sendable {

    enum CaptureError: Error {
        case createTap(OSStatus)
        case defaultOutput(OSStatus)
        case createAggregate(OSStatus)
        case tapFormat(OSStatus)
        case createIOProc(OSStatus)
        case start(OSStatus)
    }

    /// Called on a background queue with mono Float samples at `inputSampleRate`
    /// (NOT yet resampled — the engine resamples whole utterances at once to
    /// avoid per-chunk resampler-boundary distortion).
    var onAudio: (([Float]) -> Void)?

    /// The tap's native sample rate (e.g. 48000). Valid after `start`.
    private(set) var inputSampleRate: Double = 48_000

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.plus.meetingcaptions.tap.io", qos: .userInitiated)

    private let ring = FloatRingBuffer(capacity: 1 << 19) // ~10s @ 48k mono headroom
    private var tapFormat: AVAudioFormat?

    private var consumerTimer: DispatchSourceTimer?
    private var scratch = [Float](repeating: 0, count: 1 << 19)

    /// Saved so we can rebuild the tap when the default output device changes
    /// (e.g. user plugs in headphones mid-meeting).
    private var currentProcessIDs: [AudioObjectID] = []
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListenerAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    // MARK: - Lifecycle

    /// Start capturing audio.
    ///
    /// - If `processObjectIDs` is non-empty: tap exactly those process objects
    ///   (pass ALL of an app's audio-producing objects — Chrome/Electron render
    ///   through helper processes, so pass every matching object, not just one).
    /// - If empty: GLOBAL tap of all system output (nothing excluded).
    ///
    /// Per-process capture works reliably now that signing is stable (an ad-hoc
    /// cdhash churn — not the process selection — was the earlier silence cause).
    func start(processObjectIDs: [AudioObjectID]) throws {
        currentProcessIDs = processObjectIDs
        try buildTapAndAggregate()
        registerDeviceChangeListener()
    }

    /// Builds the tap + private aggregate + IOProc. Called on start and again
    /// whenever the default output device changes.
    private func buildTapAndAggregate() throws {
        let processObjectIDs = currentProcessIDs
        let desc: CATapDescription
        if processObjectIDs.isEmpty {
            desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        } else {
            desc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        }
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted            // keep audio playing to headphones

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTap)
        guard tapStatus == noErr else { throw CaptureError.createTap(tapStatus) }
        tapID = newTap

        // Resolve the current default output device UID for the aggregate.
        let outputUID = try Self.defaultOutputUID()

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MeetingCaptions-Agg",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,   // tap UID == description UUID
            ]],
        ]
        var newAgg = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAgg)
        guard aggStatus == noErr else { throw CaptureError.createAggregate(aggStatus) }
        aggregateID = newAgg

        // Read the tap's real PCM format (Float32; interleaving NOT assumed).
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let fmtStatus = AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &asbdSize, &asbd)
        guard fmtStatus == noErr, let inFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw CaptureError.tapFormat(fmtStatus)
        }
        tapFormat = inFormat

        // IOProc: realtime-safe. Downmix to mono into the ring; NO alloc/lock/log.
        // Read straight from the AudioBufferList to honor the ACTUAL layout — this
        // tap delivers INTERLEAVED stereo, which floatChannelData misreads.
        let localRing = ring
        let block: AudioDeviceIOBlock = { _, inData, _, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard abl.count > 0 else { return }

            if abl.count == 1 {
                // One buffer: either mono, or interleaved multi-channel (LRLR…).
                let buf = abl[0]
                guard let data = buf.mData else { return }
                let ch = Int(buf.mNumberChannels)
                let ptr = data.assumingMemoryBound(to: Float.self)
                let frames = Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * max(ch, 1))
                if ch <= 1 {
                    localRing.write(ptr, frames: frames)
                } else {
                    localRing.writeInterleavedDownmixed(ptr, channelCount: ch, frames: frames)
                }
            } else {
                // Multiple buffers = non-interleaved planar, one per channel.
                // Meeting audio is near-identical L/R, so the first plane suffices.
                let buf0 = abl[0]
                guard let d0 = buf0.mData else { return }
                let frames = Int(buf0.mDataByteSize) / MemoryLayout<Float>.size
                localRing.write(d0.assumingMemoryBound(to: Float.self), frames: frames)
            }
        }

        var newProc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue, block)
        guard procStatus == noErr, let newProc else { throw CaptureError.createIOProc(procStatus) }
        ioProcID = newProc

        let startStatus = AudioDeviceStart(aggregateID, newProc)
        guard startStatus == noErr else { throw CaptureError.start(startStatus) }

        // Start the consumer only once; on device-change rebuilds it keeps running
        // and just reads from the same ring, so audio is seamless.
        if consumerTimer == nil {
            startConsumer(inputSampleRate: inFormat.sampleRate)
        } else {
            inputSampleRate = inFormat.sampleRate
        }
    }

    // MARK: - Output device change → rebuild (seamless)

    private func registerDeviceChangeListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // Rebuild on the main queue to serialize with stop().
            DispatchQueue.main.async { self.rebuildForDeviceChange() }
        }
        deviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceListenerAddr, nil, block)
    }

    private func unregisterDeviceChangeListener() {
        if let block = deviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &deviceListenerAddr, nil, block)
            deviceListenerBlock = nil
        }
    }

    /// Tear down just the tap + aggregate (keep the consumer/ring) and rebuild
    /// against the new default output device.
    private func rebuildForDeviceChange() {
        guard deviceListenerBlock != nil else { return }   // not running
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        try? buildTapAndAggregate()   // rebuild against the new default output
    }

    func stop() {
        unregisterDeviceChangeListener()
        consumerTimer?.cancel()
        consumerTimer = nil
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { stop() }

    // MARK: - Consumer: ring (input rate, mono) → onAudio (still at input rate)

    private func startConsumer(inputSampleRate: Double) {
        self.inputSampleRate = inputSampleRate
        // Pull ~every 200ms; hand the raw mono samples straight to the engine.
        // NO resampling here — the engine resamples whole utterances at once,
        // which avoids the chunk-boundary distortion a stateful per-tick
        // AVAudioConverter introduces (the cause of garbled transcripts).
        let timer = DispatchSource.makeTimerSource(queue:
            DispatchQueue(label: "com.plus.meetingcaptions.tap.consumer", qos: .userInitiated))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let n = self.ring.read(into: &self.scratch, max: self.scratch.count)
            guard n > 0 else { return }
            self.onAudio?(Array(self.scratch[0..<n]))
        }
        consumerTimer = timer
        timer.resume()
    }

    // MARK: - Helpers

    private static func defaultOutputUID() throws -> String {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var devSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let st = AudioObjectGetPropertyData(sys, &devAddr, 0, nil, &devSize, &dev)
        guard st == noErr else { throw CaptureError.defaultOutput(st) }

        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        let st2 = AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &uidSize, &uid)
        guard st2 == noErr, let uid else { throw CaptureError.defaultOutput(st2) }
        return uid.takeRetainedValue() as String
    }
}
