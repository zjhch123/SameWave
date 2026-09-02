import SwiftUI
@preconcurrency import Translation  // silence Swift 6 main-actor data-race warning

/// A view modifier that hosts a single, long-lived Translation session and
/// translates the current context BLOCK as a whole (for maximum context), then
/// publishes the whole-block Chinese back to the store.
///
/// `sourceLanguage` (e.g. "en", "ja") drives the session's source; when it
/// changes SwiftUI tears down and rebuilds the `translationTask` with the new
/// language pair, so switching meeting language re-points the translator.
struct TranslationPump: ViewModifier {
    let bridge: TranslationBridge
    let sourceLanguage: String

    private var config: TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguage),
            target: Locale.Language(identifier: "zh-Hans"))
    }

    func body(content: Content) -> some View {
        content
            .translationTask(config) { session in
                do {
                    try await session.prepareTranslation()

                    // Pull the next request, translate it, repeat. The bridge coalesces
                    // per section so the pump never falls behind under dense speech —
                    // stale snapshots are skipped and the newest text is always what
                    // gets translated. An empty result signals a failed translation.
                    while let req = await bridge.next() {
                        let zh = await Self.translate(req, session: session)
                        bridge.onTranslated?(req, zh)
                    }
                } catch {
                    // Session setup failed (e.g. the language pair isn't downloaded yet);
                    // the task simply ends. SwiftUI rebuilds it when `config` changes.
                }
            }
    }

    /// Translate one request. When it carries leading context (`context ||| target`),
    /// translate the whole thing for discourse quality then split the output back to
    /// just the target portion; if the delimiter is lost in translation, fall back to
    /// translating the plain target alone. Returns "" on error (the failure contract).
    private static func translate(_ req: TranslationBridge.Request,
                                  session: TranslationSession) async -> String {
        do {
            let full = try await session.translate(req.source).targetText
            guard req.hasContext else { return full }
            if let target = extractTarget(from: full) { return target }
            // Delimiter lost → translate the target alone (context-free fallback).
            return try await session.translate(req.target).targetText
        } catch {
            return ""
        }
    }

    /// Recover the target-side translation from a combined `context ||| target` result
    /// by taking the text after the LAST delimiter occurrence. The candidate list
    /// covers how Apple Translation reformats the marker for zh output — collapsed
    /// spacing, fullwidth pipes, or a line break — and searching backwards means a pipe
    /// inside the context can't fool it. Returns nil if no delimiter survived.
    private static func extractTarget(from full: String) -> String? {
        for sep in [" ||| ", "|||", " ｜｜｜ ", "｜｜｜", " | ", "| ", "｜", "\n"] {
            if let r = full.range(of: sep, options: .backwards) {
                let tail = String(full[r.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { return tail }
            }
        }
        return nil
    }
}
