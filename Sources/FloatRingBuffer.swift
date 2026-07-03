import Foundation

/// Single-producer / single-consumer lock-free float ring buffer.
///
/// The Core Audio IOProc runs on a realtime thread where we must NOT allocate,
/// lock, or log. It only `write`s here. A normal background task `read`s on the
/// other side and does the heavy work (resample + recognition).
///
/// Correctness relies on: exactly one writer thread, exactly one reader thread,
/// and `capacity` being a power of two.
final class FloatRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>

    // Monotonic indices; wrap via `& mask`. Atomic via the platform's aligned
    // word loads/stores — good enough for one-producer/one-consumer counters.
    private var head = 0   // write index (producer only writes)
    private var tail = 0   // read index (consumer only writes)

    init(capacity: Int) {
        precondition(capacity > 0 && (capacity & (capacity - 1)) == 0,
                     "capacity must be a power of two")
        self.capacity = capacity
        self.mask = capacity - 1
        self.storage = .allocate(capacity: capacity)
        self.storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Producer side — called from the realtime IOProc. No allocation.
    /// Drops samples if the consumer has fallen behind (better than blocking audio).
    func write(_ src: UnsafePointer<Float>, frames: Int) {
        let h = head
        let t = tail
        let used = h - t
        let free = capacity - used
        let n = min(frames, free)
        guard n > 0 else { return }
        for i in 0..<n {
            storage[(h &+ i) & mask] = src[i]
        }
        head = h &+ n
    }

    /// Producer side — down-mix N non-interleaved channels to mono directly into
    /// the ring. Realtime-safe: no allocation, reads each channel pointer in place.
    func writeDownmixed(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
                        channelCount: Int, frames: Int) {
        guard channelCount > 0 else { return }
        let h = head
        let t = tail
        let free = capacity - (h - t)
        let n = min(frames, free)
        guard n > 0 else { return }
        let inv = 1.0 / Float(channelCount)
        for i in 0..<n {
            var acc: Float = 0
            for c in 0..<channelCount { acc += channels[c][i] }
            storage[(h &+ i) & mask] = acc * inv
        }
        head = h &+ n
    }

    /// Producer side — down-mix INTERLEAVED N-channel Float32 (LRLRLR…) to mono.
    /// `src` points at the first sample; consecutive channels are adjacent, then
    /// the next frame follows. Realtime-safe: no allocation.
    func writeInterleavedDownmixed(_ src: UnsafePointer<Float>,
                                   channelCount: Int, frames: Int) {
        guard channelCount > 0 else { return }
        let h = head
        let t = tail
        let free = capacity - (h - t)
        let n = min(frames, free)
        guard n > 0 else { return }
        let inv = 1.0 / Float(channelCount)
        for i in 0..<n {
            var acc: Float = 0
            let base = i * channelCount
            for c in 0..<channelCount { acc += src[base + c] }
            storage[(h &+ i) & mask] = acc * inv
        }
        head = h &+ n
    }

    /// Consumer side — drains up to `max` samples into `dst`. Returns count read.
    func read(into dst: inout [Float], max: Int) -> Int {
        let h = head
        let t = tail
        let available = h - t
        let n = Swift.min(max, available)
        guard n > 0 else { return 0 }
        if dst.count < n { dst = [Float](repeating: 0, count: n) }
        for i in 0..<n {
            dst[i] = storage[(t &+ i) & mask]
        }
        tail = t &+ n
        return n
    }

    /// Samples currently available to read.
    var count: Int { head - tail }
}
