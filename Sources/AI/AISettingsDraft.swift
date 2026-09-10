import Foundation
import Observation

/// Pending AI preferences and their service checks remain independent of vocabulary edits.
@MainActor
@Observable
final class AISettingsDraft {
    enum TestState: Equatable { case idle, testing, ok, failed(String) }
    enum ModelDiscoveryState: Equatable { case idle, loading, loaded(Int), failed(String) }

    private struct ConnectionTestResponse: Decodable {
        struct Status: Decodable { let ok: Bool }
        let status: Status
        let values: [Int]
    }

    private let settings: AISettings
    var isEnabled: Bool {
        get { settings.isEnabled }
        set {
            settings.isEnabled = newValue
            if !newValue { cancelRequests() }
        }
    }
    var providerID: String { didSet { if oldValue != providerID { connectionDetailsChanged() } } }
    var apiKey: String { didSet { if oldValue != apiKey { connectionDetailsChanged() } } }
    var customAPIAddress: String { didSet { if oldValue != customAPIAddress { connectionDetailsChanged() } } }
    var customModel: String { didSet { if oldValue != customModel { cancelConnectionTest() } } }
    var contextBudgetText: String
    private(set) var availableModels: [LLMModel] = []
    private(set) var testState: TestState = .idle
    private(set) var modelDiscoveryState: ModelDiscoveryState = .idle
    @ObservationIgnored private var testTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var testToken = UUID()
    @ObservationIgnored private var discoveryToken = UUID()

    var config: LLMProviderConfig { LLMProviderConfig.byID(providerID) }
    var isConfigured: Bool {
        AISettings.isConfigured(provider: config, apiKey: apiKey,
                                customAPIAddress: customAPIAddress, customModel: customModel)
    }
    var canFetchModels: Bool {
        isEnabled && config.isCustom && !apiKey.trimmed.isEmpty
            && OpenAIEndpointResolver.modelsURL(from: customAPIAddress) != nil
            && modelDiscoveryState != .loading
    }

    init(settings: AISettings) {
        self.settings = settings
        providerID = settings.selectedProviderID
        apiKey = settings.apiKey
        customAPIAddress = settings.customAPIAddress
        customModel = settings.customModel
        contextBudgetText = String(settings.insightContextTokenBudget)
    }

    var isDirty: Bool {
        providerID != settings.selectedProviderID || apiKey != settings.apiKey
            || customAPIAddress != settings.customAPIAddress || customModel != settings.customModel
            || contextBudget != settings.insightContextTokenBudget
    }

    // Retain incomplete input instead of silently saving the last parseable value.
    var contextBudget: Int? {
        let text = contextBudgetText.trimmed
        guard text.wholeMatch(of: /(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)/) != nil else { return nil }
        return Int(text.replacingOccurrences(of: ",", with: ""))
    }

    var isContextBudgetValid: Bool {
        guard let contextBudget else { return false }
        return (16_384...2_000_000).contains(contextBudget)
    }

    var canSave: Bool { isDirty && isContextBudgetValid }

    func save() {
        guard canSave, let contextBudget else { return }
        settings.selectedProviderID = providerID
        settings.customAPIAddress = customAPIAddress
        settings.customModel = customModel
        settings.insightContextTokenBudget = contextBudget
        if apiKey != settings.apiKey { settings.apiKey = apiKey }
        cancelRequests()
    }

    func revert() {
        providerID = settings.selectedProviderID
        apiKey = settings.apiKey
        customAPIAddress = settings.customAPIAddress
        customModel = settings.customModel
        contextBudgetText = String(settings.insightContextTokenBudget)
        connectionDetailsChanged()
    }

    func testConnection(using provider: (any LLMProvider)? = nil) {
        guard isEnabled, isConfigured, testState != .testing else { return }
        cancelConnectionTest()
        let token = testToken
        let provider = provider ?? makeProvider()
        testState = .testing
        testTask = Task {
            defer { if testToken == token { testTask = nil } }
            do {
                try Task.checkCancellation()
                let raw = try await provider.complete(
                    system: "You are a connection test assistant. Return a JSON object with status.ok set to true and values set to [1, 2].",
                    user: "ping", schema: .connectionTest)
                try Task.checkCancellation()
                guard testToken == token else { return }
                guard let response = JSONResponseParser.decode(ConnectionTestResponse.self, from: raw),
                      response.status.ok, response.values == [1, 2] else { throw LLMError.schemaViolation }
                testState = .ok
            } catch {
                guard testToken == token else { return }
                testState = error is CancellationError ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func fetchModels(load: (() async throws -> [LLMModel])? = nil) {
        guard canFetchModels else { return }
        cancelModelDiscovery()
        let token = discoveryToken
        let requestedModel = customModel
        let provider = makeProvider()
        let load = load ?? { try await provider.fetchModels() }
        modelDiscoveryState = .loading
        discoveryTask = Task {
            defer { if discoveryToken == token { discoveryTask = nil } }
            do {
                try Task.checkCancellation()
                let models = try await load()
                try Task.checkCancellation()
                guard discoveryToken == token else { return }
                availableModels = models
                if customModel == requestedModel, !models.contains(where: { $0.id == customModel }), let first = models.first {
                    customModel = first.id
                }
                modelDiscoveryState = .loaded(models.count)
            } catch {
                guard discoveryToken == token else { return }
                availableModels = []
                modelDiscoveryState = error is CancellationError ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// Dismissal releases requests and their loading states while keeping the editable draft.
    func cancelRequests() {
        cancelConnectionTest()
        cancelModelDiscovery()
    }

    private func cancelConnectionTest() {
        testToken = UUID()
        testTask?.cancel()
        testTask = nil
        testState = .idle
    }

    private func cancelModelDiscovery() {
        discoveryToken = UUID()
        discoveryTask?.cancel()
        discoveryTask = nil
        if modelDiscoveryState == .loading { modelDiscoveryState = .idle }
    }

    private func connectionDetailsChanged() {
        cancelRequests()
        availableModels = []
        modelDiscoveryState = .idle
    }

    private func makeProvider() -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(config: config, apiKey: apiKey.trimmed,
            apiAddressOverride: config.isCustom ? customAPIAddress : nil,
            modelOverride: config.isCustom ? customModel : nil)
    }
}
