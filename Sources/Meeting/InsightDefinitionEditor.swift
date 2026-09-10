import SwiftUI

struct InsightDefinitionEditor: View {
    private let isNew: Bool
    private let isDefault: Bool
    private let onSave: (InsightTemplate) throws -> Void
    private let onRemove: (() throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var template: InsightTemplate
    @State private var error: String?

    init(record: MeetingRecord, history: MeetingHistoryStore, definition: InsightDefinition?) {
        self.init(template: definition?.template, onSave: { value in
            let item = definition ?? InsightDefinition(title: value.title, prompt: value.prompt)
            item.title = value.title
            item.prompt = value.prompt
            item.scope = value.scope.rawValue
            item.automaticallyUpdates = value.automaticallyUpdates
            if definition == nil { item.record = record; history.context.insert(item) }
            try history.save()
        }, onRemove: definition.map { item in
            { history.context.delete(item); try history.save() }
        })
    }

    init(template: InsightTemplate?, isDefault: Bool = false,
         onSave: @escaping (InsightTemplate) throws -> Void, onRemove: (() throws -> Void)? = nil) {
        isNew = template == nil
        self.isDefault = isDefault
        self.onSave = onSave
        self.onRemove = onRemove
        _template = State(initialValue: template ?? InsightTemplate())
    }

    private var heading: String {
        if isDefault {
            isNew ? String(localized: "Add Default Insight") : String(localized: "Edit Default Insight")
        } else {
            isNew ? String(localized: "Add Insight") : String(localized: "Edit Insight")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: isDefault ? 12 : 16) {
                    Text(heading).font(.title2.bold())
                    if isDefault {
                        Text("Added to new meetings. Existing meetings stay unchanged.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    TextField("Title", text: $template.title).textFieldStyle(.roundedBorder)
                    Text("What should this insight analyze?")
                    TextEditor(text: $template.prompt)
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
                    Picker("Focus", selection: $template.scope) {
                        ForEach(InsightScope.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent {
                        HStack {
                            Spacer(minLength: 8)
                            Toggle("Generate automatically during recording", isOn: $template.automaticallyUpdates)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    } label: {
                        Text("Generate automatically during recording")
                        Text("New results use the app language.")
                    }
                }.padding(24)
            }
            Divider()
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 16) }
            HStack {
                if let onRemove {
                    Button("Remove Insight", role: .destructive) {
                        do {
                            try onRemove()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!template.isValid)
            }.padding(16)
        }.frame(width: 500, height: isDefault ? 490 : 440)
    }

    private func save() {
        do {
            try onSave(template.normalized)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
