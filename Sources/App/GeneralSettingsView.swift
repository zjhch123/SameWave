import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppLanguageSettings
    @Bindable var aiController: AISettingsController

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker(selection: $settings.language) {
                    Text("Follow System").tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Chinese").tag(AppLanguage.chinese)
                } label: {
                    Text("App Language")
                    Text("Saved automatically. Quit and reopen SameWave to apply language changes.")
                }
            }

            SwiftUI.Section {
                Toggle(isOn: $aiController.isEnabled) {
                    Text("Enable AI Services")
                    Text("Turning off stops AI tasks and keeps your configuration.")
                }
                .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
    }
}
