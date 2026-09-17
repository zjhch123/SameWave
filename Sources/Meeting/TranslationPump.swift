import SwiftUI
@preconcurrency import Translation  // silence Swift 6 main-actor data-race warning

struct TranslationPump: ViewModifier {
    let bridge: TranslationBridge
    let languagePair: MeetingLanguagePair

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await bridge.run(
                    prepare: { try await session.prepareTranslation() },
                    translate: { try await session.translate($0.source).targetText },
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

}
