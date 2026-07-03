import Foundation
import Observation

/// Bridges translation requests into the SwiftUI `.translationTask` closure.
///
/// Two kinds of work flow through here:
///  - `.block` — the committed context window (≤6 finalized sentences) translated
///    TOGETHER for full context; shown as the bright, refining paragraph.
///  - `.provisional` — the sentence still being spoken (Apple's volatile text),
///    translated on its own for a quick rough gist so the user doesn't wait for
///    the speaker to finish a long sentence. Shown dim; superseded when the
///    sentence finalizes and enters the block.
///
/// **Coalescing, two-slot mailbox — not a FIFO queue.** Each kind keeps only its
/// LATEST pending request; older snapshots of the same kind are dropped (their
/// content is already contained in the newer one). The two kinds have SEPARATE
/// slots so a burst of provisional updates can never evict a pending block
/// translation, and vice versa. This keeps the translator from ever falling
/// behind under dense speech: no unbounded queue, no head-of-line blocking.
///
/// The Translation framework's session is view-anchored and kept alive by an
/// in-flight async loop in `TranslationPump`.
@MainActor
@Observable
final class TranslationBridge {
    enum Kind: Sendable { case block, provisional }

    struct Request: Sendable {
        let generation: Int
        let kind: Kind
        let english: String
    }

    /// Called with (generation, kind, translated Chinese).
    var onTranslated: ((Int, Kind, String) -> Void)?

    /// Latest not-yet-taken request of each kind (overwritten on each enqueue).
    private var pendingBlock: Request?
    private var pendingProvisional: Request?
    /// The pump, suspended in `next()` waiting for work.
    private var waiter: CheckedContinuation<Request?, Never>?
    private var finished = false

    /// Enqueue the newest snapshot of `kind`, replacing any not-yet-taken one.
    func enqueue(generation: Int, kind: Kind, english: String) {
        let req = Request(generation: generation, kind: kind, english: english)
        switch kind {
        case .block: pendingBlock = req
        case .provisional: pendingProvisional = req
        }
        if let w = waiter, let next = takeNext() {
            waiter = nil
            w.resume(returning: next)
        }
    }

    /// Take the next request to translate. Block work has priority over
    /// provisional (committed text matters more than an in-progress gist).
    private func takeNext() -> Request? {
        if let b = pendingBlock { pendingBlock = nil; return b }
        if let p = pendingProvisional { pendingProvisional = nil; return p }
        return nil
    }

    /// Await the next request. Suspends until one is available; returns `nil`
    /// once `finish()` has been called so the pump loop can stop.
    func next() async -> Request? {
        if finished { return nil }
        if let n = takeNext() { return n }
        return await withCheckedContinuation { cont in
            waiter = cont
        }
    }

    /// Wake a suspended pump so its loop can terminate cleanly (teardown only).
    func finish() {
        finished = true
        pendingBlock = nil
        pendingProvisional = nil
        if let w = waiter { waiter = nil; w.resume(returning: nil) }
    }
}
