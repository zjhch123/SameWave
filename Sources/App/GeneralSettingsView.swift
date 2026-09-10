import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppLanguageSettings

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("App Language", selection: $settings.language) {
                    Text("Follow System").tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Chinese").tag(AppLanguage.chinese)
                }
            } footer: {
                Text("Saved automatically. Quit and reopen SameWave to apply language changes.")
            }
        }
        .formStyle(.grouped)
    }
}
