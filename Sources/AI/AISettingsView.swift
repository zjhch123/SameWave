import SwiftUI

/// App-wide AI settings use a draft that only reaches UserDefaults and Keychain
/// after Save. The vocabulary tab follows the same Save/Cancel interaction.
struct AISettingsView: View {
    private struct ConnectionTestResponse: Decodable {
        struct Status: Decodable {
            let ok: Bool
        }

        let status: Status
        let values: [Int]
    }

    let settings: AISettings

    // Local draft — seeded from the saved settings, edited freely, applied on Save.
    @State private var providerID: String
    @State private var apiKey: String
    @State private var customAPIAddress: String
    @State private var customModel: String
    @State private var availableModels: [LLMModel] = []

    /// Connection-test lifecycle (runs against the DRAFT, so you can validate before saving).
    private enum TestState: Equatable { case idle, testing, ok, failed(String) }
    @State private var testState: TestState = .idle
    private enum ModelDiscoveryState: Equatable {
        case idle, loading, loaded(Int), failed(String)
    }
    @State private var modelDiscoveryState: ModelDiscoveryState = .idle
    @State private var modelDiscoveryToken = UUID()
    /// Set briefly after a successful Save so the user gets confirmation feedback.
    @State private var justSaved = false

    init(settings: AISettings) {
        self.settings = settings
        _providerID = State(initialValue: settings.selectedProviderID)
        _apiKey = State(initialValue: settings.apiKey)
        _customAPIAddress = State(initialValue: settings.customAPIAddress)
        _customModel = State(initialValue: settings.customModel)
    }

    /// The provider descriptor for the DRAFT selection.
    private var draftConfig: LLMProviderConfig { LLMProviderConfig.byID(providerID) }

    /// Whether the DRAFT has enough to call an LLM (gates the test button).
    private var draftConfigured: Bool {
        AISettings.isConfigured(
            provider: draftConfig, apiKey: apiKey,
            customAPIAddress: customAPIAddress, customModel: customModel
        )
    }

    private var canFetchModels: Bool {
        draftConfig.isCustom
            && !apiKey.trimmed.isEmpty
            && OpenAIEndpointResolver.modelsURL(from: customAPIAddress) != nil
            && modelDiscoveryState != .loading
    }

    /// Whether the draft differs from the saved settings (enables Save / Cancel).
    private var isDirty: Bool {
        providerID != settings.selectedProviderID
            || apiKey != settings.apiKey
            || customAPIAddress != settings.customAPIAddress
            || customModel != settings.customModel
    }

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
                    Picker("AI Provider", selection: $providerID) {
                        ForEach(LLMProviderConfig.builtIn) { cfg in
                            Text(cfg.displayName).tag(cfg.id)
                        }
                    }
                    .onChange(of: providerID) { _, _ in connectionDetailsChanged() }

                    SecureField("API Key", text: $apiKey,
                                prompt: Text(draftConfig.keyHint))
                        .onChange(of: apiKey) { _, _ in connectionDetailsChanged() }

                    // Custom services accept whatever address the provider documents. The
                    // resolved request URL makes the normalization visible and predictable.
                    if draftConfig.isCustom {
                        TextField("API URL", text: $customAPIAddress,
                                  prompt: Text("https://api.example.com"))
                            .onChange(of: customAPIAddress) { _, _ in
                                connectionDetailsChanged()
                            }

                        if let resolved = OpenAIEndpointResolver.chatCompletionsURL(
                            from: customAPIAddress
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
                            TextField("Model ID", text: $customModel,
                                      prompt: Text("Fetch models or enter an ID"))
                                .onChange(of: customModel) { _, _ in editingChanged() }

                            if !availableModels.isEmpty {
                                Menu("Select Model") {
                                    ForEach(availableModels) { model in
                                        Button(modelLabel(model)) {
                                            customModel = model.id
                                            editingChanged()
                                        }
                                    }
                                }
                            }

                            Button(availableModels.isEmpty ? "Fetch Models" : "Refresh List") {
                                fetchModels()
                            }
                            .disabled(!canFetchModels)
                        }

                        modelDiscoveryStatus
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if draftConfig.isCustom {
                        Text("Enter a domain, an address ending in /v1, or a full /chat/completions URL. Use a model that supports Structured Outputs. You can test the connection before saving.")
                            .font(.system(size: 11))
                            .foregroundStyle(CaptionsView.meta)
                    }
                }

                SwiftUI.Section {
                    HStack(spacing: 10) {
                        Button("Test Connection") { runTest() }
                            .disabled(!draftConfigured || testState == .testing)
                        testStatus
                    }
                } footer: {
                    Text("AI features send meeting text or selected Markdown content to this provider. Refinement includes your full vocabulary; insights include only matching terms; titles include none. Audio is never uploaded. Live captions, translation, and manual vocabulary editing run locally without AI configuration.")
                        .font(.system(size: 11))
                        .foregroundStyle(CaptionsView.meta)
                }
            }
            .formStyle(.grouped)

            // Bottom action bar: draft is only applied on Save.
            Divider()
            HStack(spacing: 10) {
                if justSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.green)
                } else if isDirty {
                    Text("Unsaved changes")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                Spacer()
                Button("Cancel") { revert() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!isDirty)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
            }
            .padding(12)
        }
    }

    @ViewBuilder private var testStatus: some View {
        switch testState {
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
        switch modelDiscoveryState {
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

    // MARK: - Actions

    /// Any field edit invalidates a prior test result and clears the "Saved" flash.
    private func editingChanged() {
        testState = .idle
        justSaved = false
    }

    /// Address, key, and provider changes invalidate a previously discovered model list.
    private func connectionDetailsChanged() {
        modelDiscoveryToken = UUID()
        availableModels = []
        modelDiscoveryState = .idle
        editingChanged()
    }

    /// Commit the draft to the shared settings (persists prefs + writes the key to the
    /// Keychain via `AISettings`' setters). Only reachable when dirty.
    private func save() {
        settings.selectedProviderID = providerID
        settings.customAPIAddress = customAPIAddress
        settings.customModel = customModel
        settings.apiKey = apiKey            // triggers the Keychain write
        testState = .idle
        justSaved = true
        // Clear the "Saved" flash the next time the user edits anything.
    }

    /// Discard the draft, restoring the last saved values.
    private func revert() {
        providerID = settings.selectedProviderID
        apiKey = settings.apiKey
        customAPIAddress = settings.customAPIAddress
        customModel = settings.customModel
        availableModels = []
        modelDiscoveryState = .idle
        testState = .idle
        justSaved = false
    }

    /// Fire a minimal request using the DRAFT values, so the user can validate a config
    /// before saving it. Surfaces a readable result.
    private func runTest() {
        justSaved = false
        let cfg = draftConfig
        let provider = OpenAICompatibleProvider(
            config: cfg, apiKey: apiKey.trimmed,
            apiAddressOverride: cfg.isCustom ? customAPIAddress : nil,
            modelOverride: cfg.isCustom ? customModel : nil)
        testState = .testing
        Task { @MainActor in
            do {
                let raw = try await provider.complete(
                    system: "You are a connection test assistant. Return a JSON object with status.ok set to true and values set to [1, 2].",
                    user: "ping",
                    schema: .connectionTest
                )
                guard let response = JSONResponseParser.decode(
                    ConnectionTestResponse.self,
                    from: raw
                ), response.status.ok, response.values == [1, 2]
                else { throw LLMError.schemaViolation }
                testState = .ok
            } catch let e as LLMError {
                testState = .failed(e.errorDescription ?? "Connection failed")
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func fetchModels() {
        justSaved = false
        let token = UUID()
        modelDiscoveryToken = token
        modelDiscoveryState = .loading
        let provider = OpenAICompatibleProvider(
            config: draftConfig,
            apiKey: apiKey.trimmed,
            apiAddressOverride: customAPIAddress,
            modelOverride: customModel
        )
        Task { @MainActor in
            do {
                let models = try await provider.fetchModels()
                guard modelDiscoveryToken == token else { return }
                availableModels = models
                if !models.contains(where: { $0.id == customModel }) {
                    customModel = models[0].id
                }
                modelDiscoveryState = .loaded(models.count)
                editingChanged()
            } catch is CancellationError {
                guard modelDiscoveryToken == token else { return }
                modelDiscoveryState = .idle
            } catch let error as LLMError {
                guard modelDiscoveryToken == token else { return }
                availableModels = []
                modelDiscoveryState = .failed(error.errorDescription ?? "Could not fetch models")
            } catch {
                guard modelDiscoveryToken == token else { return }
                availableModels = []
                modelDiscoveryState = .failed(error.localizedDescription)
            }
        }
    }

    private func modelLabel(_ model: LLMModel) -> String {
        guard let owner = model.ownedBy?.trimmed, !owner.isEmpty else { return model.id }
        return "\(model.id) · \(owner)"
    }
}
