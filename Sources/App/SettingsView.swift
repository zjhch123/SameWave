import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsNavigation {
    enum Tab: Hashable { case ai, vocabulary }
    var selectedTab: Tab = .ai

    func openAISettings(using openSettings: () -> Void) {
        selectedTab = .ai
        openSettings()
    }
}
struct SettingsView: View {
    let aiSettings: AISettings
    let speechVocabularyDraft: SpeechVocabularyDraft
    let vocabularyImportController: VocabularyImportController
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            AISettingsView(settings: aiSettings)
                .tabItem {
                    Label("AI Services", systemImage: "cpu")
                }
                .tag(SettingsNavigation.Tab.ai)

            SpeechVocabularySettingsView(
                draft: speechVocabularyDraft,
                importController: vocabularyImportController
            )
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }
                .tag(SettingsNavigation.Tab.vocabulary)
        }
        .frame(width: 600, height: 500)
    }
}
