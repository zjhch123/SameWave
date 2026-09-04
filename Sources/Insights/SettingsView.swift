import SwiftUI

struct SettingsView: View {
    let insightSettings: InsightSettings
    let speechVocabularySettings: SpeechVocabularySettings

    var body: some View {
        TabView {
            InsightSettingsPane(settings: insightSettings)
                .tabItem {
                    Label("智能洞察", systemImage: "sparkles")
                }

            SpeechVocabularySettingsView(settings: speechVocabularySettings)
                .tabItem {
                    Label("词表", systemImage: "text.book.closed")
                }
        }
        .frame(width: 600, height: 500)
    }
}

/// Insight-provider settings use a draft that only reaches UserDefaults and Keychain
/// after Save. The vocabulary tab follows the same Save/Cancel interaction.
private struct InsightSettingsPane: View {
    let settings: InsightSettings

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

    init(settings: InsightSettings) {
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
        guard !apiKey.trimmed.isEmpty else { return false }
        if draftConfig.isCustom {
            return OpenAIEndpointResolver.chatCompletionsURL(from: customAPIAddress) != nil
                && !customModel.trimmed.isEmpty
        }
        return true
    }

    private var canFetchModels: Bool {
        draftConfig.isCustom
            && !apiKey.trimmed.isEmpty
            && OpenAIEndpointResolver.modelsURL(from: customAPIAddress) != nil
            && modelDiscoveryState != .loading
    }

    /// Whether the draft differs from the saved settings (enables Save / 取消).
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
                    Picker("AI 服务商", selection: $providerID) {
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
                        TextField("API 地址", text: $customAPIAddress,
                                  prompt: Text("https://api.example.com"))
                            .onChange(of: customAPIAddress) { _, _ in
                                connectionDetailsChanged()
                            }

                        if let resolved = OpenAIEndpointResolver.chatCompletionsURL(
                            from: customAPIAddress
                        ) {
                            LabeledContent("实际请求") {
                                Text(resolved.absoluteString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(CaptionsView.meta)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("模型 ID", text: $customModel,
                                      prompt: Text("获取后选择，或手动填写"))
                                .onChange(of: customModel) { _, _ in editingChanged() }

                            if !availableModels.isEmpty {
                                Menu("选择模型") {
                                    ForEach(availableModels) { model in
                                        Button(modelLabel(model)) {
                                            customModel = model.id
                                            editingChanged()
                                        }
                                    }
                                }
                            }

                            Button(availableModels.isEmpty ? "获取模型" : "刷新列表") {
                                fetchModels()
                            }
                            .disabled(!canFetchModels)
                        }

                        modelDiscoveryStatus
                    }
                } header: {
                    Text("智能洞察")
                } footer: {
                    Text(draftConfig.isCustom
                         ? "API 地址可填写域名、带 /v1 的地址或完整 /chat/completions 地址，应用会自动补全。获取模型不可用时仍可手动填写模型 ID。会议文字会发送到该服务，音频不会上传。"
                         : "智能洞察会将会议对话内容发送到你选择的服务商以生成总结与建议。字幕与翻译始终在本地进行，不受此设置影响。")
                        .font(.system(size: 11))
                        .foregroundStyle(CaptionsView.meta)
                }

                SwiftUI.Section {
                    HStack(spacing: 10) {
                        Button("测试连接") { runTest() }
                            .disabled(!draftConfigured || testState == .testing)
                        testStatus
                    }
                }
            }
            .formStyle(.grouped)
            // A settings Form is a List under the hood → it shows a scrollbar the moment
            // content is a hair taller than the window. Disable its internal scrolling and
            // let the window size to the content (fixedSize below) instead.
            .scrollDisabled(true)

            // Bottom action bar: draft is only applied on Save.
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

    @ViewBuilder private var testStatus: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("测试中…").font(.system(size: 12)).foregroundStyle(CaptionsView.muted)
            }
        case .ok:
            Label("连接成功", systemImage: "checkmark.circle.fill")
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
                Text("正在获取模型…")
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.muted)
            }
        case .loaded(let count):
            Label("已获取 \(count) 个模型", systemImage: "checkmark.circle.fill")
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

    /// Any field edit invalidates a prior test result and clears the "已保存" flash.
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
    /// Keychain via `InsightSettings`' setters). Only reachable when dirty.
    private func save() {
        settings.selectedProviderID = providerID
        settings.customAPIAddress = customAPIAddress
        settings.customModel = customModel
        settings.apiKey = apiKey            // triggers the Keychain write
        testState = .idle
        justSaved = true
        // Clear the "已保存" flash the next time the user edits anything.
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
                _ = try await provider.complete(
                    system: "你是一个连接测试助手，请只返回 JSON：{\"ok\":true}",
                    user: "ping")
                testState = .ok
            } catch let e as LLMError {
                testState = .failed(e.errorDescription ?? "连接失败")
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
                modelDiscoveryState = .failed(error.errorDescription ?? "获取模型失败")
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
