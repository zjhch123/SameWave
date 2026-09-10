import SwiftUI

struct DefaultInsightsSettingsView: View {
    let settings: DefaultInsightSettings
    @State private var editing: InsightTemplate?
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        Form {
            SwiftUI.Section {
                if let loadError = settings.loadError {
                    Text(loadError).foregroundStyle(.red)
                    Text("Reset default insights to start with Meeting Overview.")
                        .foregroundStyle(.secondary)
                    Button("Reset Default Insights", role: .destructive) {
                        perform { try settings.reset() }
                    }
                } else if settings.templates.isEmpty {
                    LabeledContent {
                        EmptyView()
                    } label: {
                        Text("No default insights")
                        Text("You can still add insights in any meeting.")
                    }
                } else {
                    ForEach(settings.templates) { template in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title).lineLimit(2).help(template.title)
                                Text("\(template.scope.label) · \(template.automaticallyUpdates ? String(localized: "Automatic") : String(localized: "Manual"))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: 12) {
                                Button("Edit") { editing = template }
                                    .accessibilityLabel("Edit \(template.title)")
                                Button(role: .destructive) {
                                    perform { try settings.remove(id: template.id) }
                                } label: {
                                    Label("Remove Insight", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(template.title)")
                                .help("Remove Insight")
                            }
                            .fixedSize()
                            .controlSize(.small)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            } header: {
                HStack {
                    Text("Default Insights")
                    Spacer()
                    Button("Add Insight", systemImage: "plus") { adding = true }
                        .controlSize(.small)
                        .disabled(settings.loadError != nil)
                        .accessibilityIdentifier("defaultInsights.add")
                }
            } footer: {
                Text("Added to new meetings. Existing meetings stay unchanged.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { template in
            InsightDefinitionEditor(template: template, isDefault: true,
                onSave: { try settings.save($0) }, onRemove: { try settings.remove(id: template.id) })
        }
        .sheet(isPresented: $adding) {
            InsightDefinitionEditor(template: nil, isDefault: true, onSave: { try settings.save($0) })
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
