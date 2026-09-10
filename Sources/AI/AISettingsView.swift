import SwiftUI

/// Preferences save as edited; service checks never dismiss Settings.
struct AISettingsView: View {
    @Bindable var controller: AISettingsController
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case key, address, model, context }

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("AI Provider", selection: $controller.providerID) {
                    ForEach(LLMProviderConfig.builtIn) { cfg in
                        Text(cfg.displayName).tag(cfg.id)
                    }
                }

                SecureField("API Key", text: $controller.apiKey,
                            prompt: Text(controller.config.keyHint))
                    .focused($focusedField, equals: .key)
                if let error = controller.apiKeyStorageError {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Retry") { controller.retrySavingAPIKey() }
                    }
                }

                if controller.config.isCustom {
                    TextField(text: $controller.customAPIAddress, prompt: Text("https://api.example.com")) {
                        Text("API URL")
                        Text("Supports a base URL or full endpoint.")
                    }
                    .focused($focusedField, equals: .address)
                    if !controller.customAPIAddress.isEmpty && !controller.isCustomAddressValid {
                        Text("Enter a valid HTTP or HTTPS URL.")
                            .font(.caption).foregroundStyle(.red)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField(text: $controller.customModel, prompt: Text("Fetch models or enter an ID")) {
                            Text("Model ID")
                            Text("The model must support Structured Outputs.")
                        }
                        .focused($focusedField, equals: .model)
                        if !controller.availableModels.isEmpty {
                            Menu("Select Model") {
                                ForEach(controller.availableModels) { model in
                                    Button(modelLabel(model)) { controller.customModel = model.id }
                                }
                            }
                        }
                        Button(controller.availableModels.isEmpty ? String(localized: "Fetch Models") : String(localized: "Refresh List")) {
                            controller.fetchModels()
                        }
                        .disabled(!controller.canFetchModels)
                    }
                    modelDiscoveryStatus
                }

                TextField(text: $controller.contextBudgetText) {
                    Text("Model context window (tokens)")
                    Text("Use your model’s token limit; for example, 1,000,000 for a 1M model.")
                }
                .focused($focusedField, equals: .context)
                if !controller.isContextBudgetValid {
                    Text("Enter a context window from 16,384 to 2,000,000 tokens.")
                        .font(.caption).foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Button("Test Connection") { controller.testConnection() }
                        .disabled(!controller.isConfigured || controller.testState == .testing)
                    testStatus
                }

            } header: {
                Text("Connection")
            } footer: {
                if !controller.isEnabled {
                    Text("Enable AI Services in General to edit these settings.")
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!controller.isEnabled)
        .onSubmit { focusedField = nil }
        .onDisappear { controller.cancelRequests() }
    }

    @ViewBuilder private var testStatus: some View {
        switch controller.testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…").font(.system(size: 12)).foregroundStyle(CaptionsView.muted)
            }
        case .ok:
            Label("Connected",
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
        switch controller.modelDiscoveryState {
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
