import Foundation
import Observation
import Security

/// App-wide provider configuration shared by insights, refinement, titles and vocabulary
/// generation. Non-secret preferences use UserDefaults; the API key is persisted only
/// in Keychain. Feature availability reacts to the same saved configuration.
@MainActor
@Observable
final class AISettings {
    static let defaultContextTokenBudget = 1_000_000

    /// The master switch applies immediately, independently of the connection draft.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if oldValue && !isEnabled { onDisable?() }
        }
    }
    /// App assembly cancels every retained AI owner synchronously when disabled.
    @ObservationIgnored var onDisable: (() -> Void)?

    /// Selected provider id (matches `LLMProviderConfig.id`). Persisted in UserDefaults.
    var selectedProviderID: String {
        didSet { defaults.set(selectedProviderID, forKey: Keys.provider) }
    }
    /// Custom API address (host, versioned base, or complete Chat Completions endpoint).
    var customAPIAddress: String {
        didSet { defaults.set(customAPIAddress, forKey: Keys.customAPIAddress) }
    }
    /// Custom model id (only used for the "custom" provider).
    var customModel: String {
        didSet { defaults.set(customModel, forKey: Keys.customModel) }
    }

    /// Conservative full-input preflight budget; the user sets the provider's supported window.
    var insightContextTokenBudget: Int {
        didSet { defaults.set(insightContextTokenBudget, forKey: "insight.contextTokenBudget") }
    }

    var modelIdentity: String {
        let config = selectedConfig
        return "\(config.displayName) / \(config.isCustom ? customModel : config.defaultModel)"
    }

    /// The API key, backed by the Keychain. Setting to empty deletes it.
    var apiKey: String {
        didSet {
            let trimmed = apiKey.trimmed
            if trimmed.isEmpty { KeychainStore.delete(Keys.apiKey) }
            else { KeychainStore.set(trimmed, for: Keys.apiKey) }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, initialAPIKey: String? = nil) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let savedBudget = defaults.integer(forKey: "insight.contextTokenBudget")
        insightContextTokenBudget = savedBudget > 0 ? savedBudget : Self.defaultContextTokenBudget
        let persistedProviderID = defaults.string(forKey: Keys.provider)
        let supportedProvider = persistedProviderID.flatMap { id in
            LLMProviderConfig.builtIn.first { $0.id == id }
        }
        selectedProviderID = supportedProvider?.id ?? LLMProviderConfig.qwen.id
        customAPIAddress = defaults.string(forKey: Keys.customAPIAddress) ?? ""
        customModel = defaults.string(forKey: Keys.customModel) ?? ""
        // A host-app XCTest process is unsigned and must never prompt for or read the
        // user's real API key before the test bundle can start. A key saved for a now-
        // unsupported provider is also kept disabled so it cannot be sent to Qwen by
        // the default-provider selection; the user must explicitly configure again.
        let mayLoadSavedKey = ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil
            && supportedProvider != nil
        apiKey = initialAPIKey ?? (mayLoadSavedKey
            ? KeychainStore.get(Keys.apiKey) ?? ""
            : "")
    }

    /// The currently-selected provider descriptor.
    var selectedConfig: LLMProviderConfig { LLMProviderConfig.byID(selectedProviderID) }

    /// All AI features require a key and, for custom services, a valid endpoint and model.
    var isConfigured: Bool {
        Self.isConfigured(
            provider: selectedConfig, apiKey: apiKey,
            customAPIAddress: customAPIAddress, customModel: customModel
        )
    }

    var isAvailable: Bool { isEnabled && isConfigured }

    var settingsActionTitle: String {
        isEnabled ? String(localized: "Configure AI Services") : String(localized: "Enable AI Services")
    }

    /// Shared validation for saved configuration and the Settings connection-test draft.
    static func isConfigured(provider: LLMProviderConfig, apiKey: String,
                             customAPIAddress: String, customModel: String) -> Bool {
        guard !apiKey.trimmed.isEmpty else { return false }
        if provider.isCustom {
            return OpenAIEndpointResolver.chatCompletionsURL(from: customAPIAddress) != nil
                && !customModel.trimmed.isEmpty
        }
        return true
    }

    /// Each AI operation takes a provider snapshot from the shared saved configuration.
    func makeProvider() -> LLMProvider? {
        guard isAvailable else { return nil }
        let cfg = selectedConfig
        return OpenAICompatibleProvider(
            config: cfg, apiKey: apiKey.trimmed,
            apiAddressOverride: cfg.isCustom ? customAPIAddress : nil,
            modelOverride: cfg.isCustom ? customModel : nil)
    }

    private enum Keys {
        static let enabled = "ai.isEnabled"
        static let provider = "insight.providerID"
        static let customAPIAddress = "insight.customAPIAddress"
        static let customModel = "insight.customModel"
        static let apiKey = "insight.apiKey"      // Keychain account name
    }
}

/// Tiny Keychain wrapper for storing the API key as a generic password, scoped to this
/// app's bundle id. The `Security` API is a synchronous C interface; these calls are
/// fast and made only from the main actor (settings edits), so no extra threading.
enum KeychainStore {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.plus.samewave"
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String, for account: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete-then-add is the simplest idempotent upsert for the Keychain.
        SecItemDelete(baseQuery(account) as CFDictionary)
        var attrs = baseQuery(account)
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
