import Foundation

enum JSONResponseParser {
    static func decode<Value: Decodable>(_ type: Value.Type, from raw: String) -> Value? {
        guard let data = raw.trimmed.data(using: .utf8) else { return nil }
        // Callers turn nil into their schema-contract error at the feature boundary.
        return try? JSONDecoder().decode(type, from: data)
    }
}
