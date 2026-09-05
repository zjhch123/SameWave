import SwiftUI
import UniformTypeIdentifiers

struct SpeechVocabularySettingsView: View {
    let draft: SpeechVocabularyDraft
    let importController: VocabularyImportController

    @Environment(\.openWindow) private var openWindow
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @State private var isChoosingMarkdown = false
    @State private var justSaved = false

    var body: some View {
        @Bindable var draft = draft

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("One word or phrase per line")
                    .font(.headline)

                TextEditor(text: $draft.text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor))
                    }
                    .onChange(of: draft.text) { _, _ in justSaved = false }

                HStack {
                    Text("Terms: \(draft.phrases.count)")
                    Spacer()
                    Text("Blank lines and duplicates are removed when you save")
                }
                .font(.system(size: 11))
                .foregroundStyle(CaptionsView.meta)

                HStack(spacing: 10) {
                    Button {
                        if importController.hasActiveWorkflow {
                            openWindow(id: VocabularyImportWindow.windowID)
                        } else {
                            isChoosingMarkdown = true
                        }
                    } label: {
                        Label("Generate from Markdown", systemImage: "doc.badge.plus")
                    }
                    .disabled(!importController.canStartOrResume)

                    if !importController.isConfigured {
                        Button("Configure AI Services") {
                            settingsNavigation.selectedTab = .ai
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .help("Configure AI services to generate vocabulary from Markdown")
                    }
                    Spacer()
                }

                Text("Vocabulary helps English speech recognition and takes effect when you next start or resume a meeting. AI generation and review open in a separate window.")
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.meta)
            }
            .padding(20)

            Divider()
            HStack(spacing: 10) {
                if justSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.green)
                } else if draft.isDirty {
                    Text("Unsaved changes")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                Spacer()
                Button("Cancel") {
                    draft.revert()
                    justSaved = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(!draft.isDirty)
                Button("Save") {
                    draft.save()
                    justSaved = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isDirty)
            }
            .padding(12)
        }
        .fileImporter(
            isPresented: $isChoosingMarkdown,
            allowedContentTypes: VocabularyImportWindow.markdownContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if importController.handleFileSelection(result) {
                openWindow(id: VocabularyImportWindow.windowID)
            }
        }
    }
}
