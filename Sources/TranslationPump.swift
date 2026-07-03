import SwiftUI
@preconcurrency import Translation  // silence Swift 6 main-actor data-race warning

/// A view modifier that hosts a single, long-lived Translation session and
/// translates the current context BLOCK as a whole (for maximum context), then
/// publishes the whole-block Chinese back to the store.
struct TranslationPump: ViewModifier {
    let bridge: TranslationBridge

    private let config = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "zh-Hans"))

    func body(content: Content) -> some View {
        content
            .translationTask(config) { session in
                do {
                    try await session.prepareTranslation()

                    // Pull the next request (block work prioritized over provisional),
                    // translate it, repeat. The bridge coalesces per-kind so the pump
                    // never falls behind under dense speech — stale snapshots are
                    // skipped, and the newest text is always what gets translated.
                    while let req = await bridge.next() {
                        do {
                            let zh = try await session.translate(req.english).targetText
                            bridge.onTranslated?(req.generation, req.kind, zh)
                        } catch {
                            bridge.onTranslated?(req.generation, req.kind, "")
                        }
                    }
                } catch {
                    print("Translation setup failed:", error)
                }
            }
    }
}
