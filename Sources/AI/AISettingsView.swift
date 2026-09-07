import SwiftUI

/// AI preferences commit only through Save; their draft survives presentation changes.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var draft: AISettingsDraft

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SwiftUI.Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Services for SameWave")
                            .font(.headline)
                        Text("One configuration for insights, transcript refinement, meeting titles, and Markdown vocabulary generation. Configure and save to enable all AI features.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                SwiftUI.Section {
                    Picker("AI Provider", selection: $draft.providerID) {
                        ForEach(LLMProviderConfig.builtIn) { cfg in
                            Text(cfg.displayName).tag(cfg.id)
                        }
                    }

                    SecureField("API Key", text: $draft.apiKey,
                                prompt: Text(draft.config.keyHint))

                    // Custom services accept whatever address the provider documents. The
                    // resolved request URL makes the normalization visible and predictable.
                    if draft.config.isCustom {
                        TextField("API URL", text: $draft.customAPIAddress,
                                  prompt: Text("https://api.example.com"))

                        if let resolved = OpenAIEndpointResolver.chatCompletionsURL(
                            from: draft.customAPIAddress
                        ) {
                            LabeledContent("Request URL") {
                                Text(resolved.absoluteString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(CaptionsView.meta)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                        }

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

                            Button(draft.availableModels.isEmpty ? "Fetch Models" : "Refresh List") {
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
                        Text("Enter a domain, an address ending in /v1, or a full /chat/completions URL. Use a model that supports Structured Outputs. You can test the connection before saving.")
                            .font(.system(size: 11))
                            .foregroundStyle(CaptionsView.meta)
                    }
                }

                SwiftUI.Section {
                    TextField("Model context window (tokens)", value: $draft.contextBudget, format: .number)
                    if draft.contextBudget < 16_384 || draft.contextBudget > 2_000_000 {
                        Text("Enter a context window from 16,384 to 2,000,000 tokens.").font(.caption).foregroundStyle(.red)
                    }
                    Text("Enter the selected model's supported context window, for example 1,000,000 for a 1M model. Save applies it to new insight requests. The check conservatively estimates the complete meeting, vocabulary, instructions, and output allowance; it does not measure exact tokens. No meeting text is truncated. The service enforces its actual limit.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SwiftUI.Section {
                    HStack(spacing: 10) {
                        Button("Test Connection") { draft.testConnection() }
                            .disabled(!draft.isConfigured || draft.testState == .testing)
                        testStatus
                    }
                } footer: {
                    Text("AI features send meeting text or selected Markdown content to this provider. Refinement includes personal vocabulary; insights include the complete meeting and personal vocabulary plus the full original transcript; titles include no vocabulary. Attaching a document alone does not send it. Audio is never uploaded. Live captions, translation, and manual vocabulary editing run locally without AI configuration.")
                        .font(.system(size: 11))
                        .foregroundStyle(CaptionsView.meta)
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
