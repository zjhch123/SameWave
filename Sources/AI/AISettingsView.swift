import SwiftUI

/// The master switch is immediate; connection preferences commit through Save.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var draft: AISettingsDraft

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SwiftUI.Section {
                    Toggle("Enable AI Services", isOn: $draft.isEnabled)
                        .toggleStyle(.switch)
                } footer: {
                    Text("Applies immediately. Turning off stops AI tasks and keeps your configuration.")
                }

                SwiftUI.Section {
                    Picker("AI Provider", selection: $draft.providerID) {
                        ForEach(LLMProviderConfig.builtIn) { cfg in
                            Text(cfg.displayName).tag(cfg.id)
                        }
                    }

                    SecureField("API Key", text: $draft.apiKey,
                                prompt: Text(draft.config.keyHint))

                    if draft.config.isCustom {
                        TextField("API URL", text: $draft.customAPIAddress,
                                  prompt: Text("https://api.example.com"))

                        HStack(spacing: 10) {
                            TextField("Model ID", text: $draft.customModel,
                                      prompt: Text("Fetch models or enter an ID"))

                            if !draft.availableModels.isEmpty {
                                Menu("Select Model") {
                                    ForEach(draft.availableModels) { model in
                                        Button(modelLabel(model)) {
                                            draft.customModel = model.id
                                        }
                                    }
                                }
                            }

                            Button(draft.availableModels.isEmpty ? String(localized: "Fetch Models") : String(localized: "Refresh List")) {
                                draft.fetchModels()
                            }
                            .disabled(!draft.canFetchModels)
                        }

                        modelDiscoveryStatus
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if draft.config.isCustom {
                        Text("Supports a base URL or full endpoint. The model must support Structured Outputs.")
                            .font(.system(size: 11))
                            .foregroundStyle(CaptionsView.meta)
                    }
                }

                SwiftUI.Section {
                    TextField("Model context window (tokens)", value: $draft.contextBudget, format: .number)
                    if draft.contextBudget < 16_384 || draft.contextBudget > 2_000_000 {
                        Text("Enter a context window from 16,384 to 2,000,000 tokens.").font(.caption).foregroundStyle(.red)
                    }
                    Text("Use your model’s token limit; for example, 1,000,000 for a 1M model.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SwiftUI.Section {
                    HStack(spacing: 10) {
                        Button("Test Connection") { draft.testConnection() }
                            .disabled(!draft.isEnabled || !draft.isConfigured || draft.testState == .testing)
                        testStatus
                    }
                }
            }
            .formStyle(.grouped)

            // Bottom action bar: draft is only applied on Save.
            Divider()
            HStack(spacing: 10) {
                if draft.isDirty {
                    Text("Unsaved changes")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                Spacer()
                Button("Cancel") { draft.revert(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { draft.save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isDirty || draft.contextBudget < 16_384 || draft.contextBudget > 2_000_000)
            }
            .padding(12)
        }
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
            Label("Connected", systemImage: "checkmark.circle.fill")
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
