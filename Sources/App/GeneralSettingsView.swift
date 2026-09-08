import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppLanguageSettings

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SwiftUI.Section {
                    Picker("App Language", selection: $settings.language) {
                        Text("Follow System").tag(AppLanguage.system)
                        Text("English").tag(AppLanguage.english)
                        Text("Chinese").tag(AppLanguage.chinese)
                    }
                } footer: {
                    Text("Language changes are saved automatically. Quit and reopen SameWave to apply them.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onExitCommand { dismiss() }
    }
}
