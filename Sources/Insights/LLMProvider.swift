import Foundation

/// The one abstraction the insight layer depends on. Everything above it (the engine,
/// the settings, the UI) speaks only to this protocol and never knows which vendor is
/// behind it — so adding/replacing a provider never touches upstream code.
///
/// Deliberately minimal: a single "send a system + user prompt, get the text back"
/// call. That maps 1:1 onto the OpenAI `/chat/completions` Structured Outputs contract
/// implemented by the supported Qwen and Kimi models, so a lone
/// `OpenAICompatibleProvider` satisfies both. Non-streaming on purpose:
/// each insight pass returns a short JSON blob, so waiting for the whole response is
/// simpler than streaming and costs nothing perceptible.
protocol InsightProvider: Sendable {
    /// Send `system` + `user` messages and require the assistant content to match the
    /// supplied strict JSON Schema. Throws `LLMError` on any transport or API failure.
    func complete(system: String, user: String,
                  schema: LLMResponseSchema) async throws -> String
}

/// A request-scoped Structured Outputs contract. Every AI use case owns one of these,
/// while the provider only knows how to put it on the wire.
struct LLMResponseSchema: Encodable, Sendable {
    let name: String
    let schema: JSONValue
    let strict = true

    static let connectionTest = LLMResponseSchema(
        name: "connection_test",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "status": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "ok": .object([
                            "type": .string("boolean"),
                            "description": .string("连接测试成功时返回 true")
                        ])
                    ]),
                    "required": .array([.string("ok")]),
                    "additionalProperties": .bool(false)
                ]),
                "values": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .integer(2),
                    "maxItems": .integer(2)
                ])
            ]),
            "required": .array([.string("status"), .string("values")]),
            "additionalProperties": .bool(false)
        ])
    )
}

/// Minimal JSON value needed to encode provider-independent JSON Schemas without
/// introducing an untyped `[String: Any]` boundary or a third-party dependency.
enum JSONValue: Encodable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

/// A user-readable failure, mapped from HTTP status / transport errors so the UI can
/// show something actionable instead of a raw NSError — mirroring the app's existing
/// habit of surfacing capture problems in `statusMessage` rather than swallowing them.
enum LLMError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured          // no provider/key set up yet
    case unauthorized           // 401/403 — bad or missing key
    case rateLimited            // 429 — too many requests / quota
    case server(Int)            // other non-2xx
    case network(String)        // transport failure (offline, DNS, timeout)
    case invalidRequest(String) // 400, including an unsupported/invalid JSON Schema
    case badResponse            // 2xx but body wasn't the expected shape
    case emptyContent           // model returned no usable content
    case schemaViolation        // assistant content did not match the requested schema
    case refused(String)        // model or provider declined to produce the requested data
    case truncated              // finish_reason=length; JSON content is incomplete
    case modelListingUnavailable // endpoint does not expose a usable /models list

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置 AI 服务，请在设置（⌘,）中选择服务商并填写密钥。"
        case .unauthorized:  return "密钥无效或无权限（401）。请检查设置中的 API Key。"
        case .rateLimited:   return "请求过于频繁或额度不足（429），请稍后再试。"
        case .server(let c): return "服务返回错误（\(c)）。"
        case .network(let m): return "网络请求失败：\(m)"
        case .invalidRequest(let m): return "AI 服务拒绝了请求：\(m)"
        case .badResponse:   return "无法解析服务返回的内容。"
        case .emptyContent:  return "服务未返回有效内容。"
        case .schemaViolation:
            return "AI 服务未按 JSON Schema 返回结构化内容，请检查当前模型或网关是否支持该格式。"
        case .refused(let m): return "AI 拒绝了该请求：\(m)"
        case .truncated: return "AI 输出被截断，未返回完整结果。"
        case .modelListingUnavailable:
            return "服务未提供可用模型列表，请手动填写模型 ID。"
        }
    }
}

/// One model returned by an OpenAI-compatible `/models` endpoint. The raw `id` is sent
/// back unchanged because gateways commonly encode routing information into it.
struct LLMModel: Decodable, Equatable, Identifiable {
    let id: String
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }
}

/// A vendor descriptor — the ENTIRE per-vendor surface. Adding a provider is adding a
/// row here; nothing else changes. `apiAddress` is the complete Chat Completions URL
/// endpoints (verified against each vendor's docs). Every listed built-in model supports
/// strict `json_schema` Structured Outputs; vendors that only offer JSON mode are not
/// exposed because this app no longer accepts best-effort structured data.
struct LLMProviderConfig: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// Complete Chat Completions endpoint for built-in providers. Custom addresses are
    /// normalized separately so users may paste a host, versioned base, or full endpoint.
    let apiAddress: String
    /// Default model id. It must continue to support strict Structured Outputs.
    let defaultModel: String
    /// Upper clamp for temperature (Kimi/Moonshot only accepts [0,1]); nil = no clamp.
    let maxTemperature: Double?
    /// True for the "custom" row whose address/model come from the user, not this table.
    let isCustom: Bool

    /// Placeholder shown in the settings key field (helps users grab the right key).
    var keyHint: String

    init(id: String, displayName: String, apiAddress: String, defaultModel: String,
         maxTemperature: Double? = nil, isCustom: Bool = false, keyHint: String = "") {
        self.id = id
        self.displayName = displayName
        self.apiAddress = apiAddress
        self.defaultModel = defaultModel
        self.maxTemperature = maxTemperature
        self.isCustom = isCustom
        self.keyHint = keyHint
    }
}

extension LLMProviderConfig {
    /// The built-in provider table contains only documented strict-schema models.
    static let qwen = LLMProviderConfig(
        id: "qwen", displayName: "通义千问（阿里）",
        apiAddress: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        defaultModel: "qwen3.8-flash",
        keyHint: "sk-… （dashscope 控制台）")

    static let kimi = LLMProviderConfig(
        id: "kimi", displayName: "Kimi（月之暗面）",
        apiAddress: "https://api.moonshot.cn/v1/chat/completions",
        defaultModel: "kimi-k3",
        maxTemperature: 1.0,
        keyHint: "sk-… （platform.moonshot.cn）")

    /// The escape hatch: any other OpenAI-compatible endpoint. Address + model come
    /// from the user's settings, not from this row.
    static let custom = LLMProviderConfig(
        id: "custom", displayName: "自定义（OpenAI 兼容）",
        apiAddress: "", defaultModel: "",
        isCustom: true,
        keyHint: "你的 API Key")

    static let builtIn: [LLMProviderConfig] = [qwen, kimi, custom]

    /// Look up a config by id; obsolete persisted ids resolve to the current default.
    static func byID(_ id: String) -> LLMProviderConfig {
        builtIn.first { $0.id == id } ?? qwen
    }
}
