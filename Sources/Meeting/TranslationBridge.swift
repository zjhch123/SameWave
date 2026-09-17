import Foundation
import Observation

/// A serial, latest-value mailbox. Each consumer owns its wake-up stream so SwiftUI
/// cancellation cannot permanently close the mailbox used by later sessions.
@MainActor
@Observable
final class TranslationBridge {
    struct Request: Equatable, Sendable {
        let id = UUID()
        let sessionID: UUID
        let generation: Int
        let sectionId: Int
        let source: String
    }

    var onTranslated: ((Request, String) -> Void)?
    var onFailed: ((Request) -> Void)?
    private(set) var revision = 0

    private var pending: [Int: Request] = [:]
    private var order: [Int] = []
    private var readyAt: [Int: ContinuousClock.Instant] = [:]
    private var lastDispatch: [Int: ContinuousClock.Instant] = [:]
    private var inFlight: Request?
    private var consumerID: UUID?
    private var unavailable = false
    @ObservationIgnored private var signal: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var cancelTranslation: (() -> Void)?
    @ObservationIgnored private var idleWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    var isIdle: Bool { pending.isEmpty && inFlight == nil }

    func enqueue(sessionID: UUID, generation: Int, sectionId: Int, source: String) {
        let request = Request(sessionID: sessionID, generation: generation, sectionId: sectionId,
                              source: source)
        guard !unavailable else {
            onFailed?(request)
            return
        }
        if pending[sectionId] == nil {
            order.append(sectionId)
            let coalesced = ContinuousClock.now.advanced(by: .milliseconds(60))
            readyAt[sectionId] = max(coalesced, lastDispatch[sectionId]?.advanced(by: .milliseconds(400)) ?? coalesced)
        }
        pending[sectionId] = request
        signal?.yield()
    }

    func cancel(sectionId: Int) {
        pending.removeValue(forKey: sectionId)
        readyAt.removeValue(forKey: sectionId)
        order.removeAll { $0 == sectionId }
        resumeIdleWaitersIfNeeded()
    }

    func cancelPending() {
        pending.removeAll()
        readyAt.removeAll()
        order.removeAll()
        resumeIdleWaitersIfNeeded()
    }

    /// Start/resume retries service preparation through a fresh SwiftUI session.
    func restart() {
        if let consumerID { finishConsumer(consumerID) }
        unavailable = false
        revision += 1
    }

    /// The framework boundary injects I/O; mailbox lifetime, failures, deadlines,
    /// and response ownership can be exercised without Apple Translation resources.
    func run(requestTimeout: Duration = .seconds(15),
             prepare: () async throws -> Void,
             translate: (Request) async throws -> String,
             cancel: @escaping () -> Void) async {
        if let consumerID { finishConsumer(consumerID) }
        let id = UUID()
        let signals = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        consumerID = id
        unavailable = false
        signal = signals.continuation
        cancelTranslation = cancel
        signals.continuation.yield()
        defer { finishConsumer(id) }
        await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await prepare()
                try Task.checkCancellation()
                for await _ in signals.stream {
                    guard !Task.isCancelled, consumerID == id else { return }
                    while consumerID == id, !Task.isCancelled, let sectionID = order.first {
                        if let deadline = readyAt[sectionID] {
                            try await ContinuousClock().sleep(until: deadline)
                        }
                        guard consumerID == id, !Task.isCancelled else { return }
                        guard order.first == sectionID else { continue }
                        guard let request = takeNext() else { continue }
                        let deadline = Task { @MainActor [weak self] in
                            do { try await Task.sleep(for: requestTimeout) }
                            catch { return }
                            guard let self, self.consumerID == id, self.inFlight?.id == request.id else { return }
                            self.finishConsumer(id)
                        }
                        defer { deadline.cancel() }
                        do {
                            let translated = try await translate(request)
                            guard consumerID == id, !Task.isCancelled else { return }
                            if translated.trimmed.isEmpty { onFailed?(request) }
                            else { onTranslated?(request, translated) }
                        } catch {
                            guard consumerID == id, !Task.isCancelled else { return }
                            onFailed?(request)
                        }
                        inFlight = nil
                        resumeIdleWaitersIfNeeded()
                    }
                }
            } catch {
                // The consumer's defer settles queued work and fails subsequent
                // enqueues until restart; draining the queue only once is insufficient.
                return
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishConsumer(id) }
        }
    }

    private func takeNext() -> Request? {
        guard let sectionId = order.first else { return nil }
        order.removeFirst()
        readyAt.removeValue(forKey: sectionId)
        lastDispatch[sectionId] = .now
        inFlight = pending.removeValue(forKey: sectionId)
        return inFlight
    }

    private func finishConsumer(_ id: UUID) {
        guard consumerID == id else { return }
        consumerID = nil
        unavailable = true
        signal?.finish()
        signal = nil
        let cancel = cancelTranslation
        cancelTranslation = nil
        let failed = (inFlight.map { [$0] } ?? []) + order.compactMap { pending[$0] }
        inFlight = nil
        pending.removeAll()
        readyAt.removeAll()
        lastDispatch.removeAll()
        order.removeAll()
        failed.forEach { onFailed?($0) }
        cancel?()
        resumeIdleWaitersIfNeeded()
    }

    func waitUntilIdle(timeout: Duration) async -> Bool {
        if isIdle { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            idleWaiters[id] = continuation
            Task { @MainActor [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                self?.idleWaiters.removeValue(forKey: id)?.resume(returning: false)
            }
        }
    }

    private func resumeIdleWaitersIfNeeded() {
        guard isIdle else { return }
        let continuations = Array(idleWaiters.values)
        idleWaiters.removeAll()
        continuations.forEach { $0.resume(returning: true) }
    }
}
