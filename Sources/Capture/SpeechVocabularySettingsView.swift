import SwiftUI
import UniformTypeIdentifiers

struct SpeechVocabularySettingsView: View {
    let draft: SpeechVocabularyDraft
    let importController: VocabularyImportController

    @Environment(\.openWindow) private var openWindow
    @State private var isChoosingMarkdown = false
    @State private var justSaved = false

    var body: some View {
        @Bindable var draft = draft

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("每行一个词或短语")
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
                    Text("\(draft.phrases.count) 个词条")
                    Spacer()
                    Text("空行和重复词条会在保存时移除")
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
                        Label("从 Markdown 生成", systemImage: "doc.badge.plus")
                    }
                    .disabled(!importController.canStartOrResume)

                    if !importController.isConfigured {
                        Text("请先配置智能洞察")
                            .font(.system(size: 11))
                            .foregroundStyle(CaptionsView.meta)
                    }
                    Spacer()
                }

                Text("词表用于英文识别，在下次开始或恢复会议时生效。AI 生成与审核会在独立窗口中完成。")
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
                } else if draft.isDirty {
                    Text("有未保存的更改")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                Spacer()
                Button("取消") {
                    draft.revert()
                    justSaved = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(!draft.isDirty)
                Button("保存") {
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
