import SwiftUI
@preconcurrency import Translation  // silence Swift 6 main-actor data-race warning

/// A view modifier that hosts a single, long-lived Translation session and
/// translates the current context BLOCK as a whole (for maximum context), then
/// publishes the translated target block back to the store.
///
/// SwiftUI tears down and rebuilds the `translationTask` when either side of the
/// language pair changes. Equal source and target languages do not host a translation
/// session at all; the coordinator writes the recognized source directly to captions.
struct TranslationPump: ViewModifier {
    let bridge: TranslationBridge
    let languagePair: MeetingLanguagePair

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await bridge.run(
                    prepare: { try await session.prepareTranslation() },
                    translate: { try await Self.translate($0, session: session) },
                    cancel: { session.cancel() }
                )
            }
            .onChange(of: languagePair, initial: true) { _, pair in
                configuration = pair.needsTranslation ? TranslationSession.Configuration(
                    source: Locale.Language(identifier: pair.source.translationIdentifier),
                    target: Locale.Language(identifier: pair.target.translationIdentifier)
                ) : nil
            }
            .onChange(of: bridge.revision) { _, _ in configuration?.invalidate() }
    }

    /// Translate one request. When it carries leading context (`context ||| target`),
    /// translate the whole thing for discourse quality then split the output back to
    /// just the target portion; if the delimiter is lost in translation, fall back to
    /// translating the plain target alone.
    private static func translate(_ req: TranslationBridge.Request,
                                  session: TranslationSession) async throws -> String {
        let full = try await session.translate(req.source).targetText
        guard req.hasContext else { return full }
        if let target = extractTarget(from: full) { return target }
        return try await session.translate(req.target).targetText
    }

    /// Recover the target-side translation from a combined `context ||| target` result
    /// by taking the text after the LAST delimiter occurrence. The candidate list
    /// covers how Apple Translation may reformat the marker — collapsed spacing,
    /// fullwidth pipes, or a line break — and searching backwards means a pipe inside
    /// the context can't fool it. Returns nil if no delimiter survived.
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
