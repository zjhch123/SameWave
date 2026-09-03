import SwiftUI

struct SpeechVocabularySettingsView: View {
    let settings: SpeechVocabularySettings

    @State private var draft: String
    @State private var justSaved = false

    init(settings: SpeechVocabularySettings) {
        self.settings = settings
        _draft = State(initialValue: settings.phrases.joined(separator: "\n"))
    }

    private var draftPhrases: [String] {
        SpeechVocabularySettings.phrases(from: draft)
    }

    private var isDirty: Bool {
        draftPhrases != settings.phrases
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("每行一个词或短语")
                    .font(.headline)

                TextEditor(text: $draft)
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
                    .onChange(of: draft) { _, _ in justSaved = false }

                HStack {
                    Text("\(draftPhrases.count) 个词条")
                    Spacer()
                    Text("空行和重复词条会在保存时移除")
                }
                .font(.system(size: 11))
                .foregroundStyle(CaptionsView.meta)

                Text("仅用于英文识别，内容保存在本机。新词表会在下次开始或恢复会议时生效。")
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.meta)
            }
            .padding(20)

            Divider()
            HStack(spacing: 10) {
                if justSaved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.green)
                } else if isDirty {
                    Text("有未保存的更改")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                Spacer()
                Button("取消") { revert() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!isDirty)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
            }
            .padding(12)
        }
    }

    private func save() {
        settings.save(draftPhrases)
        draft = settings.phrases.joined(separator: "\n")
        justSaved = true
    }

    private func revert() {
        draft = settings.phrases.joined(separator: "\n")
        justSaved = false
    }
}
