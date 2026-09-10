import Foundation
import Observation

/// Binds directly to persisted preferences and owns only cancellable service checks.
@MainActor
@Observable
final class AISettingsController {
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
    var providerID: String {
        get { settings.selectedProviderID }
        set {
            guard newValue != providerID else { return }
            settings.selectedProviderID = newValue
            connectionDetailsChanged()
        }
    }
    var apiKey: String {
        get { settings.apiKey }
        set {
            guard newValue != apiKey else { return }
            settings.apiKey = newValue
            connectionDetailsChanged()
        }
    }
    var customAPIAddress: String {
        get { settings.customAPIAddress }
        set {
            guard newValue != customAPIAddress else { return }
            settings.customAPIAddress = newValue
            connectionDetailsChanged()
        }
    }
    var customModel: String {
        get { settings.customModel }
        set {
            guard newValue != customModel else { return }
            settings.customModel = newValue
            cancelConnectionTest()
        }
    }
    var contextBudgetText: String {
        get { settings.contextBudgetText }
        set { settings.contextBudgetText = newValue }
    }
    var isContextBudgetValid: Bool { settings.insightContextTokenBudget != nil }
    var isCustomAddressValid: Bool {
        OpenAIEndpointResolver.chatCompletionsURL(from: customAPIAddress) != nil
    }
    var apiKeyStorageError: String? { settings.apiKeyStorageError }
    func retrySavingAPIKey() { settings.persistAPIKey() }
    private(set) var availableModels: [LLMModel] = []
    private(set) var testState: TestState = .idle
    private(set) var modelDiscoveryState: ModelDiscoveryState = .idle
    @ObservationIgnored private var testTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var testToken = UUID()
    @ObservationIgnored private var discoveryToken = UUID()

    var config: LLMProviderConfig { LLMProviderConfig.byID(providerID) }
    var isConfigured: Bool { settings.isConfigured }
    var canFetchModels: Bool {
        isEnabled && apiKeyStorageError == nil && config.isCustom && !apiKey.trimmed.isEmpty
            && OpenAIEndpointResolver.modelsURL(from: customAPIAddress) != nil
            && modelDiscoveryState != .loading
    }

    init(settings: AISettings) {
        self.settings = settings
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

    /// Dismissal releases requests and their loading states; preferences are already saved.
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
