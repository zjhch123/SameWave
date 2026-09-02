import Foundation

/// The one abstraction the insight layer depends on. Everything above it (the engine,
/// the settings, the UI) speaks only to this protocol and never knows which vendor is
/// behind it — so adding/replacing a provider never touches upstream code.
///
/// Deliberately minimal: a single "send a system + user prompt, get the text back"
/// call. That maps 1:1 onto the frozen OpenAI `/chat/completions` contract that every
/// target vendor (DeepSeek / 通义千问 / 智谱 GLM / Kimi) implements, so a lone
/// `OpenAICompatibleProvider` satisfies it for all of them. Non-streaming on purpose:
/// each insight pass returns a short JSON blob, so waiting for the whole response is
/// simpler than streaming and costs nothing perceptible.
protocol InsightProvider: Sendable {
    /// Send `system` + `user` messages, return the assistant's raw text (expected to be
    /// a JSON object matching `InsightResult`). Throws `LLMError` on any failure.
    func complete(system: String, user: String) async throws -> String
}

/// A user-readable failure, mapped from HTTP status / transport errors so the UI can
/// show something actionable instead of a raw NSError — mirroring the app's existing
/// habit of surfacing capture problems in `statusMessage` rather than swallowing them.
enum LLMError: Error, LocalizedError, Equatable {
    case notConfigured          // no provider/key set up yet
    case unauthorized           // 401/403 — bad or missing key
    case rateLimited            // 429 — too many requests / quota
    case server(Int)            // other non-2xx
    case network(String)        // transport failure (offline, DNS, timeout)
    case badResponse            // 2xx but body wasn't the expected shape
    case emptyContent           // model returned no usable content

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置 AI 服务，请在设置（⌘,）中选择服务商并填写密钥。"
        case .unauthorized:  return "密钥无效或无权限（401）。请检查设置中的 API Key。"
        case .rateLimited:   return "请求过于频繁或额度不足（429），请稍后再试。"
        case .server(let c): return "服务返回错误（\(c)）。"
        case .network(let m): return "网络请求失败：\(m)"
        case .badResponse:   return "无法解析服务返回的内容。"
        case .emptyContent:  return "服务未返回有效内容。"
        }
    }
}

/// A vendor descriptor — the ENTIRE per-vendor surface. Adding a provider is adding a
/// row here; nothing else changes. `baseURL`s are the official OpenAI-compatible
/// endpoints (verified against each vendor's docs). `maxTemperature` and `needsJSONHint`
/// are the only real behavioral quirks (Kimi caps temp at 1; Qwen/DeepSeek require the
/// literal word "json" in the prompt when using json_object mode — which our system
/// prompt always contains, so the flag is documentation more than logic).
struct LLMProviderConfig: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// Base URL WITHOUT a trailing `/chat/completions` — the provider appends the path.
    /// May include a `/v1`-style version segment where the vendor requires it.
    let baseURL: String
    /// Default model id. The one recurring maintenance chore is bumping this when a
    /// vendor retires a name (e.g. DeepSeek deprecates `deepseek-chat` 2026-07-24).
    let defaultModel: String
    /// Upper clamp for temperature (Kimi/Moonshot only accepts [0,1]); nil = no clamp.
    let maxTemperature: Double?
    /// Whether json_object mode requires the word "json" in the prompt (Qwen/DeepSeek).
    let needsJSONHint: Bool
    /// True for the "custom" row whose baseURL/model come from the user, not this table.
    let isCustom: Bool

    /// Placeholder shown in the settings key field (helps users grab the right key).
    var keyHint: String

    init(id: String, displayName: String, baseURL: String, defaultModel: String,
         maxTemperature: Double? = nil, needsJSONHint: Bool = false,
         isCustom: Bool = false, keyHint: String = "") {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.maxTemperature = maxTemperature
        self.needsJSONHint = needsJSONHint
        self.isCustom = isCustom
        self.keyHint = keyHint
    }
}

extension LLMProviderConfig {
    /// The built-in provider table. Chinese-user-facing, all officially OpenAI-compatible
    /// and directly reachable from mainland China. This static list + the model-name
    /// constants are essentially the whole maintenance surface for the LLM layer.
    static let deepseek = LLMProviderConfig(
        id: "deepseek", displayName: "DeepSeek（深度求索）",
        baseURL: "https://api.deepseek.com",
        defaultModel: "deepseek-chat",
        needsJSONHint: true,
        keyHint: "sk-… （platform.deepseek.com）")

    static let qwen = LLMProviderConfig(
        id: "qwen", displayName: "通义千问（阿里）",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        defaultModel: "qwen-plus",
        needsJSONHint: true,
        keyHint: "sk-… （dashscope 控制台）")

    static let glm = LLMProviderConfig(
        id: "glm", displayName: "智谱 GLM",
        baseURL: "https://open.bigmodel.cn/api/paas/v4",
        defaultModel: "glm-4-flash",
        keyHint: "… （open.bigmodel.cn）")

    static let kimi = LLMProviderConfig(
        id: "kimi", displayName: "Kimi（月之暗面）",
        baseURL: "https://api.moonshot.cn/v1",
        defaultModel: "moonshot-v1-8k",
        maxTemperature: 1.0,
        keyHint: "sk-… （platform.moonshot.cn）")

    /// The escape hatch: any other OpenAI-compatible endpoint. baseURL + model come
    /// from the user's settings, not from this row.
    static let custom = LLMProviderConfig(
        id: "custom", displayName: "自定义（OpenAI 兼容）",
        baseURL: "", defaultModel: "",
        isCustom: true,
        keyHint: "你的 API Key")

    static let builtIn: [LLMProviderConfig] = [deepseek, qwen, glm, kimi, custom]

    /// Look up a config by id; falls back to DeepSeek if an unknown id was persisted.
    static func byID(_ id: String) -> LLMProviderConfig {
        builtIn.first { $0.id == id } ?? deepseek
    }
}
