import Foundation

/// The ONE concrete provider. Speaks the frozen OpenAI `/chat/completions` wire format
/// (`messages[]` in, `choices[0].message.content` out) that DeepSeek / 通义千问 /
/// 智谱 GLM / Kimi all implement, so this single ~120-line type reaches every built-in
/// vendor — the only thing that varies is the `LLMProviderConfig` (base URL, model,
/// quirks) it's handed. There is no "compatibility layer" to rot: the request/response
/// Codable structs declare only the minimal fields we use, and the protocol is
/// additive-only, so new server-side fields are ignored rather than breaking us.
///
/// Non-streaming: one request, await the whole JSON blob, return its content. An insight
/// pass is a short object, so streaming would add complexity for no felt benefit. (If
/// ever needed, `URLSession.bytes(for:)` yields SSE lines natively — a `data:`-prefixed
/// line loop is the only addition, and this type's `complete` signature stays the same.)
struct OpenAICompatibleProvider: InsightProvider {
    let config: LLMProviderConfig
    let apiKey: String
    /// Effective base URL: the config's, or the user-supplied one for the custom row.
    let baseURLOverride: String?
    /// Effective model: the config's default, or the user-supplied one for custom.
    let modelOverride: String?

    init(config: LLMProviderConfig, apiKey: String,
         baseURLOverride: String? = nil, modelOverride: String? = nil) {
        self.config = config
        self.apiKey = apiKey
        self.baseURLOverride = baseURLOverride
        self.modelOverride = modelOverride
    }

    private var baseURL: String {
        (baseURLOverride?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? config.baseURL
    }
    private var model: String {
        (modelOverride?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? config.defaultModel
    }

    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.trimmed.isEmpty, !baseURL.isEmpty, !model.isEmpty else {
            throw LLMError.notConfigured
        }
        guard let url = URL(string: baseURL.trimmingTrailingSlash + "/chat/completions") else {
            throw LLMError.network("无效的服务地址")
        }

        // Clamp temperature to the vendor's ceiling (Kimi caps at 1). Low temp keeps the
        // structured output stable.
        let temperature = min(0.3, config.maxTemperature ?? .greatestFiniteMagnitude)

        let payload = ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system),
                       .init(role: "user", content: user)],
            temperature: temperature,
            responseFormat: .init(type: "json_object"))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        do {
            req.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw LLMError.badResponse
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw LLMError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403:  throw LLMError.unauthorized
        case 429:       throw LLMError.rateLimited
        default:        throw LLMError.server(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw LLMError.badResponse
        }
        let trimmed = content.trimmed
        guard !trimmed.isEmpty else { throw LLMError.emptyContent }
        return trimmed
    }
}

// MARK: - Minimal wire types (only the fields we send/read)

/// Request body. Declares only what we use; the frozen, additive-only chat/completions
/// contract guarantees the server ignores nothing we omit and we ignore what we don't map.
private struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct ResponseFormat: Encodable { let type: String }
    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }
}

/// Response body — we only need `choices[0].message.content`. Extra server fields
/// (usage, id, etc.) are simply not decoded.
private struct ChatResponse: Decodable {
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String? }
    let choices: [Choice]
}

private extension String {
    /// Drop a single trailing slash so `base + "/chat/completions"` never doubles up.
    var trimmingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
