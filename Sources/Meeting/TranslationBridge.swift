import Foundation
import Observation

/// Bridges translation requests into the SwiftUI `.translationTask` closure.
///
/// Work is keyed by **section** (spec Rule B — translation is a per-section axis).
/// A section is re-translated as its source grows (spec §十 reschedule_translation on
/// every ASR update) and once more, authoritatively, when it seals. Several
/// sealed-but-not-yet-DONE sections can be in flight after back-to-back interrupts
/// (spec §十二).
///
/// **Coalescing mailbox — not a FIFO queue.** Each `sectionId` slot keeps only its
/// LATEST pending request; a newer snapshot of the same section supersedes the older
/// (its text is a superset, or it's the sealing "final"). Distinct sections never
/// evict each other, so dense speech on one section can't starve another's
/// translation — no unbounded queue, no head-of-line blocking, and the translator
/// self-throttles to the freshest text it can keep up with.
@MainActor
@Observable
final class TranslationBridge {
    struct Request: Sendable {
        let generation: Int
        let sectionId: Int
        /// What the translator receives: either the plain target, or (when
        /// `hasContext`) `context + " ||| " + target` so the model has leading
        /// discourse context. The pump splits the result back to the target portion.
        let source: String
        /// The plain target text only — used for the delimiter-split fallback (translate
        /// the target alone if the delimiter is lost in the combined output).
        let target: String
        /// True when translating the frozen source of a sealed section — its arrival
        /// drives the section to DONE.
        let isFinal: Bool
        /// True when `source` is a combined context+target string needing a split.
        let hasContext: Bool
    }

    /// Called with the completed request and its translated Chinese.
    var onTranslated: ((Request, String) -> Void)?

    /// Latest not-yet-taken request per section, overwritten on enqueue.
    private var pending: [Int: Request] = [:]
    /// Oldest-waiting-first order of section slots, so distinct sections are serviced
    /// fairly rather than by hash order.
    private var order: [Int] = []
    private var waiter: CheckedContinuation<Request?, Never>?

    /// Enqueue the newest snapshot for `sectionId`, replacing any pending one.
    func enqueue(generation: Int, sectionId: Int, source: String, target: String,
                 isFinal: Bool, hasContext: Bool) {
        if pending[sectionId] == nil { order.append(sectionId) }
        pending[sectionId] = Request(generation: generation, sectionId: sectionId,
                                     source: source, target: target,
                                     isFinal: isFinal, hasContext: hasContext)
        if waiter != nil, let next = takeNext() { wake(with: next) }
    }

    /// Drop any pending work for a section (e.g. it was pruned).
    func cancel(sectionId: Int) {
        if pending.removeValue(forKey: sectionId) != nil {
            order.removeAll { $0 == sectionId }
        }
    }

    /// Oldest-waiting section first (fair, FIFO across sections).
    private func takeNext() -> Request? {
        while let sid = order.first {
            order.removeFirst()
            if let r = pending.removeValue(forKey: sid) { return r }
        }
        return nil
    }

    /// Await the next request; suspends until one is available. (The pump loop that
    /// calls this is owned by a SwiftUI `.translationTask`, which cancels it on
    /// teardown, so an abandoned continuation is harmless.)
    func next() async -> Request? {
        if let n = takeNext() { return n }
        return await withCheckedContinuation { cont in waiter = cont }
    }

    /// Resume a suspended `next()` with `req`, clearing the waiter.
    private func wake(with req: Request?) {
        guard let w = waiter else { return }
        waiter = nil
        w.resume(returning: req)
    }
}
