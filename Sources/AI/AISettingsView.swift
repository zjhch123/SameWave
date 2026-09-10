import SwiftUI

/// Enablement is immediate; connection actions never dismiss Settings.
struct AISettingsView: View {
    @Bindable var draft: AISettingsDraft
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case key, address, model, context }

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Enable AI Services", isOn: $draft.isEnabled)
                    .toggleStyle(.switch)
            } footer: {
                Text("Applies immediately. No save needed. Turning off stops AI tasks and keeps your configuration.")
            }

            SwiftUI.Section {
                Picker("AI Provider", selection: $draft.providerID) {
                    ForEach(LLMProviderConfig.builtIn) { cfg in
                        Text(cfg.displayName).tag(cfg.id)
                    }
                }

                SecureField("API Key", text: $draft.apiKey,
                            prompt: Text(draft.config.keyHint))
                    .focused($focusedField, equals: .key)

                if draft.config.isCustom {
                    TextField("API URL", text: $draft.customAPIAddress,
                              prompt: Text("https://api.example.com"))
                        .focused($focusedField, equals: .address)

                    HStack(spacing: 10) {
                        TextField("Model ID", text: $draft.customModel,
                                  prompt: Text("Fetch models or enter an ID"))
                            .focused($focusedField, equals: .model)
                        if !draft.availableModels.isEmpty {
                            Menu("Select Model") {
                                ForEach(draft.availableModels) { model in
                                    Button(modelLabel(model)) { draft.customModel = model.id }
                                }
                            }
                        }
                        Button(draft.availableModels.isEmpty ? String(localized: "Fetch Models") : String(localized: "Refresh List")) {
                            draft.fetchModels()
                        }
                        .disabled(!draft.canFetchModels)
                    }
                    modelDiscoveryStatus
                    Text("Supports a base URL or full endpoint. The model must support Structured Outputs.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                TextField("Model context window (tokens)", text: $draft.contextBudgetText)
                    .focused($focusedField, equals: .context)
                if !draft.isContextBudgetValid {
                    Text("Enter a context window from 16,384 to 2,000,000 tokens.")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Use your model’s token limit; for example, 1,000,000 for a 1M model.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Test Connection") { draft.testConnection() }
                        .disabled(!draft.isEnabled || !draft.isConfigured || draft.testState == .testing)
                    testStatus
                }

                HStack(spacing: 10) {
                    if draft.isDirty {
                        Text("Unsaved changes").foregroundStyle(.secondary)
                    } else {
                        Text("No unsaved changes").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Revert") { draft.revert() }
                        .disabled(!draft.isDirty)
                        .accessibilityIdentifier("ai.revert")
                    Button("Save Changes") { draft.save() }
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("ai.save")
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Connection changes apply only when saved.")
            }
        }
        .formStyle(.grouped)
        .onSubmit { focusedField = nil }
        .onDisappear { draft.cancelRequests() }
    }

    @ViewBuilder private var testStatus: some View {
        switch draft.testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…").font(.system(size: 12)).foregroundStyle(CaptionsView.muted)
            }
        case .ok:
            Label(draft.isDirty ? String(localized: "Connection works · not saved") : String(localized: "Connected"),
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(CaptionsView.danger)
                .lineLimit(2)
        }
    }

    @ViewBuilder private var modelDiscoveryStatus: some View {
        switch draft.modelDiscoveryState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Fetching models…")
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.muted)
            }
        case .loaded(let count):
            Label("Models found: \(count)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(CaptionsView.danger)
                .lineLimit(2)
        }
    }

    private func modelLabel(_ model: LLMModel) -> String {
        guard let owner = model.ownedBy?.trimmed, !owner.isEmpty else { return model.id }
        return "\(model.id) · \(owner)"
    }
}
