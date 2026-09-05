import Foundation

/// Shared AI transport boundary. Each feature owns its prompt and response schema;
/// providers return a complete response without depending on any feature's state.
protocol LLMProvider: Sendable {
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
                            "description": .string("Return true when the connection test succeeds")
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
        case .notConfigured: return "AI is not configured. Open Settings → AI Services (⌘,), complete the configuration, and save."
        case .unauthorized:  return "Invalid API key or access denied (401). Check your API key in Settings → AI Services."
        case .rateLimited:   return "Rate limit or quota exceeded (429). Please try again later."
        case .server(let c): return "The service returned an error (\(c))."
        case .network(let m): return "Network request failed: \(m)"
        case .invalidRequest(let m): return "The AI service rejected the request: \(m)"
        case .badResponse:   return "Could not parse the service response."
        case .emptyContent:  return "The service returned no usable content."
        case .schemaViolation:
            return "The AI response does not match the JSON Schema. Check whether your model or gateway supports Structured Outputs."
        case .refused(let m): return "AI refused the request: \(m)"
        case .truncated: return "The AI response was truncated and is incomplete."
        case .modelListingUnavailable:
            return "The service did not return a usable model list. Enter a model ID manually."
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
        id: "qwen", displayName: "Qwen (Alibaba)",
        apiAddress: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        defaultModel: "qwen3.8-flash",
        keyHint: "sk-… (DashScope console)")

    static let kimi = LLMProviderConfig(
        id: "kimi", displayName: "Kimi (Moonshot AI)",
        apiAddress: "https://api.moonshot.cn/v1/chat/completions",
        defaultModel: "kimi-k3",
        maxTemperature: 1.0,
        keyHint: "sk-… (platform.moonshot.cn)")

    /// The escape hatch: any other OpenAI-compatible endpoint. Address + model come
    /// from the user's settings, not from this row.
    static let custom = LLMProviderConfig(
        id: "custom", displayName: "Custom (OpenAI Compatible)",
        apiAddress: "", defaultModel: "",
        isCustom: true,
        keyHint: "Your API Key")

    static let builtIn: [LLMProviderConfig] = [qwen, kimi, custom]

    /// Look up a config by id; obsolete persisted ids resolve to the current default.
    static func byID(_ id: String) -> LLMProviderConfig {
        builtIn.first { $0.id == id } ?? qwen
    }
}
