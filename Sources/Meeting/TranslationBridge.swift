import Foundation
import Observation

/// A latest-value mailbox for Apple Translation work.
///
/// Pending snapshots are coalesced per section while different sections keep FIFO
/// fairness. In-flight work is counted explicitly so pause/stop can wait for the
/// authoritative sealed-section translations instead of sleeping for an arbitrary
/// amount of time.
@MainActor
@Observable
final class TranslationBridge {
    struct Request: Equatable, Sendable {
        let sessionID: UUID
        let generation: Int
        let sectionId: Int
        let source: String
        let target: String
        let isFinal: Bool
        let hasContext: Bool
    }

    var onTranslated: ((Request, String) -> Void)?
    var onFailed: ((Request) -> Void)?

    private var pending: [Int: Request] = [:]
    private var order: [Int] = []
    private var inFlightCount = 0

    @ObservationIgnored private let signals: AsyncStream<Void>
    @ObservationIgnored private let signalContinuation: AsyncStream<Void>.Continuation
    @ObservationIgnored private var idleWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        signals = pair.stream
        signalContinuation = pair.continuation
    }

    var isIdle: Bool { pending.isEmpty && inFlightCount == 0 }

    func enqueue(sessionID: UUID, generation: Int, sectionId: Int, source: String,
                 target: String, isFinal: Bool, hasContext: Bool) {
        if pending[sectionId] == nil { order.append(sectionId) }
        pending[sectionId] = Request(
            sessionID: sessionID,
            generation: generation,
            sectionId: sectionId,
            source: source,
            target: target,
            isFinal: isFinal,
            hasContext: hasContext
        )
        signalContinuation.yield()
    }

    func cancel(sectionId: Int) {
        if pending.removeValue(forKey: sectionId) != nil {
            order.removeAll { $0 == sectionId }
            resumeIdleWaitersIfNeeded()
        }
    }

    func cancelPending() {
        pending.removeAll()
        order.removeAll()
        resumeIdleWaitersIfNeeded()
    }

    func failPending() {
        let failed = order.compactMap { pending[$0] }
        pending.removeAll()
        order.removeAll()
        failed.forEach { onFailed?($0) }
        resumeIdleWaitersIfNeeded()
    }

    func next() async -> Request? {
        if let request = takeNext() { return request }
        for await _ in signals {
            if Task.isCancelled { return nil }
            if let request = takeNext() { return request }
        }
        return nil
    }

    func complete(_ request: Request) {
        if inFlightCount > 0 { inFlightCount -= 1 }
        resumeIdleWaitersIfNeeded()
    }

    func waitUntilIdle(timeout: Duration) async -> Bool {
        if isIdle { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            idleWaiters[id] = continuation
            Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.resumeWaiter(id: id, result: false)
            }
        }
    }

    private func takeNext() -> Request? {
        while let sectionId = order.first {
            order.removeFirst()
            if let request = pending.removeValue(forKey: sectionId) {
                inFlightCount += 1
                return request
            }
        }
        return nil
    }

    private func resumeIdleWaitersIfNeeded() {
        guard isIdle else { return }
        let continuations = Array(idleWaiters.values)
        idleWaiters.removeAll()
        continuations.forEach { $0.resume(returning: true) }
    }

    private func resumeWaiter(id: UUID, result: Bool) {
        idleWaiters.removeValue(forKey: id)?.resume(returning: result)
    }
}
