import Foundation

/// The ONE concrete provider. Speaks the OpenAI `/chat/completions` Structured Outputs
/// wire format (`messages[]` plus strict `json_schema` in, structured message content
/// out). The only vendor-specific values are the address, model, and temperature ceiling.
/// Request/response Codable structs declare only the fields this app uses.
///
/// Non-streaming: one request, await the whole JSON blob, return its content. An insight
/// pass is a short object, so streaming would add complexity for no felt benefit.
struct OpenAICompatibleProvider: InsightProvider {
    static let completionTimeout: TimeInterval = 60

    let config: LLMProviderConfig
    let apiKey: String
    /// Effective API address: the config's, or the user-supplied one for the custom row.
    let apiAddressOverride: String?
    /// Effective model: the config's default, or the user-supplied one for custom.
    let modelOverride: String?

    init(config: LLMProviderConfig, apiKey: String,
         apiAddressOverride: String? = nil, modelOverride: String? = nil) {
        self.config = config
        self.apiKey = apiKey
        self.apiAddressOverride = apiAddressOverride
        self.modelOverride = modelOverride
    }

    private var apiAddress: String {
        (apiAddressOverride?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? config.apiAddress
    }
    private var model: String {
        (modelOverride?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? config.defaultModel
    }

    func complete(system: String, user: String,
                  schema: LLMResponseSchema) async throws -> String {
        guard !apiKey.trimmed.isEmpty, !apiAddress.isEmpty, !model.isEmpty else {
            throw LLMError.notConfigured
        }
        guard let url = OpenAIEndpointResolver.chatCompletionsURL(from: apiAddress) else {
            throw LLMError.network("无效的服务地址")
        }

        // Clamp temperature to the vendor's ceiling (Kimi caps at 1). Low temp keeps the
        // structured output stable.
        let temperature = min(0.3, config.maxTemperature ?? .greatestFiniteMagnitude)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = Self.completionTimeout
        do {
            req.httpBody = try Self.makeRequestBody(
                model: model,
                system: system,
                user: user,
                temperature: temperature,
                schema: schema
            )
        } catch {
            throw LLMError.badResponse
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw LLMError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403:  throw LLMError.unauthorized
        case 429:       throw LLMError.rateLimited
        case 400:
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?
                .error.message.trimmed
            throw LLMError.invalidRequest(
                message.flatMap { $0.isEmpty ? nil : $0 } ?? "请求参数或 JSON Schema 不被支持"
            )
        default:        throw LLMError.server(http.statusCode)
        }

        return try Self.parseContent(from: data)
    }

    static func parseContent(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let choice = decoded.choices.first else { throw LLMError.badResponse }
        if let refusal = choice.message.refusal?.trimmed, !refusal.isEmpty {
            throw LLMError.refused(refusal)
        }
        switch choice.finishReason {
        case "stop": break
        case "length": throw LLMError.truncated
        case "content_filter": throw LLMError.refused("内容安全策略阻止了输出")
        default: throw LLMError.badResponse
        }
        guard let content = choice.message.content else { throw LLMError.emptyContent }
        let trimmed = content.trimmed
        guard !trimmed.isEmpty else { throw LLMError.emptyContent }
        return trimmed
    }

    /// Kept internal so tests can verify the exact Structured Outputs wire contract
    /// without performing a network request.
    static func makeRequestBody(model: String, system: String, user: String,
                                temperature: Double,
                                schema: LLMResponseSchema) throws -> Data {
        let payload = ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system),
                       .init(role: "user", content: user)],
            temperature: temperature,
            responseFormat: .init(type: "json_schema", jsonSchema: schema)
        )
        return try JSONEncoder().encode(payload)
    }

    /// Fetch model IDs from the `/models` sibling of the resolved Chat Completions URL.
    /// This is deliberately optional UI assistance: callers can still type an ID when a
    /// compatible service does not implement model listing.
    func fetchModels() async throws -> [LLMModel] {
        guard !apiKey.trimmed.isEmpty, !apiAddress.isEmpty else {
            throw LLMError.notConfigured
        }
        guard let url = OpenAIEndpointResolver.modelsURL(from: apiAddress) else {
            throw LLMError.network("无效的服务地址")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw LLMError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403:  throw LLMError.unauthorized
        case 429:       throw LLMError.rateLimited
        case 404, 405:  throw LLMError.modelListingUnavailable
        default:        throw LLMError.server(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
            throw LLMError.badResponse
        }
        var seen = Set<String>()
        let models = decoded.data.filter { !$0.id.trimmed.isEmpty && seen.insert($0.id).inserted }
        guard !models.isEmpty else { throw LLMError.modelListingUnavailable }
        return models
    }
}

// MARK: - Minimal wire types (only the fields we send/read)

/// Request body. Declares only what we use; the frozen, additive-only chat/completions
/// contract guarantees the server ignores nothing we omit and we ignore what we don't map.
private struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct ResponseFormat: Encodable {
        let type: String
        let jsonSchema: LLMResponseSchema

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }
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
    struct Choice: Decodable {
        let message: Message
        let finishReason: String

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    struct Message: Decodable {
        let content: String?
        let refusal: String?
    }
    let choices: [Choice]
}

private struct ErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

private struct ModelListResponse: Decodable {
    let data: [LLMModel]
}

/// Accepts the address forms users commonly find in provider documentation and resolves
/// them to concrete OpenAI-compatible endpoints. A bare host uses the OpenAI-standard
/// `/v1`; an existing path is treated as a versioned base unless it is already complete.
enum OpenAIEndpointResolver {
    static func chatCompletionsURL(from address: String) -> URL? {
        guard var components = components(from: address) else { return nil }
        components.fragment = nil

        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty || path == "/" {
            path = "/v1/chat/completions"
        } else if !path.lowercased().hasSuffix("/chat/completions") {
            path += "/chat/completions"
        }
        components.path = path
        return components.url
    }

    static func modelsURL(from address: String) -> URL? {
        guard let chatURL = chatCompletionsURL(from: address),
              var components = URLComponents(url: chatURL, resolvingAgainstBaseURL: false)
        else { return nil }
        let suffix = "/chat/completions"
        guard components.path.lowercased().hasSuffix(suffix) else { return nil }
        components.path = String(components.path.dropLast(suffix.count)) + "/models"
        return components.url
    }

    private static func components(from address: String) -> URLComponents? {
        let trimmed = address.trimmed
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        let value: String
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            value = trimmed
        } else if lowercased.hasPrefix("localhost")
                    || lowercased.hasPrefix("127.")
                    || lowercased.hasPrefix("0.0.0.0")
                    || lowercased.hasPrefix("[::1]") {
            value = "http://" + trimmed
        } else {
            value = "https://" + trimmed
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else { return nil }
        return components
    }
}
