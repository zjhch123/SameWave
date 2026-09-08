import SwiftUI

struct InsightDefinitionEditor: View {
    let record: MeetingRecord
    let history: MeetingHistoryStore
    let definition: InsightDefinition?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var prompt: String
    @State private var automatic: Bool
    @State private var scope: InsightScope
    @State private var error: String?

    init(record: MeetingRecord, history: MeetingHistoryStore, definition: InsightDefinition?) {
        self.record = record
        self.history = history
        self.definition = definition
        _title = State(initialValue: definition?.title ?? "")
        _prompt = State(initialValue: definition?.prompt ?? "")
        _automatic = State(initialValue: definition?.automaticallyUpdates ?? false)
        _scope = State(initialValue: definition?.configuration.scope ?? .cumulative)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(definition == nil ? String(localized: "Add Insight") : String(localized: "Edit Insight")).font(.title2.bold())
                    TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                    Text("What should this insight analyze?")
                    TextEditor(text: $prompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(height: 140)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                        .accessibilityLabel("Insight instructions")
                    Picker("Focus", selection: $scope) {
                        ForEach(InsightScope.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Generate automatically during recording", isOn: $automatic)
                    Text("New results use the app language.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            Divider()
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 16) }
            HStack {
                if let definition {
                    Button("Remove Insight", role: .destructive) {
                        do {
                            history.context.delete(definition)
                            try history.save()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmed.isEmpty || prompt.trimmed.isEmpty)
            }.padding(16)
        }.frame(width: 500, height: 440)
    }

    private func save() {
        do {
            let item = definition ?? InsightDefinition(title: title.trimmed, prompt: prompt.trimmed)
            item.title = title.trimmed
            item.prompt = prompt.trimmed
            item.scope = scope.rawValue
            item.automaticallyUpdates = automatic
            if definition == nil { item.record = record; history.context.insert(item) }
            try history.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
