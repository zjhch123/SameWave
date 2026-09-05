import Foundation

/// The structured result of one insight generation — the SINGLE definition that is
/// reused three ways: (1) the JSON schema we instruct the LLM to return, (2) the data
/// source the SwiftUI cards render from, and (3) the payload we persist onto a
/// `MeetingRecord` (encoded to `insightJSON`). Keeping it in one place means the model
/// shape, the render, and the on-disk format can never drift apart.
///
/// Every field is optional-by-emptiness: a quiet stretch of meeting yields empty
/// arrays / nil `answer`, and the cards simply render nothing for those — never an
/// error. `Equatable` lets the engine skip a redundant UI publish when the result
/// didn't actually change.
struct InsightResult: Codable, Equatable {
    /// One or two sentences: what the conversation is about *right now*.
    var topic: String
    /// Concrete "what you could ask / say next" nudges to move the meeting forward.
    var suggestions: [String]
    /// When the other side just posed a question, a reference answer you can lean on.
    /// `nil` when nobody asked anything — the answer card only appears when useful.
    var answer: String?
    /// Extracted action items (who owes what).
    var todos: [InsightTodo]
    /// Decisions the conversation has landed on.
    var decisions: [String]

    /// An empty result — the idle/placeholder value before any generation lands, and
    /// the graceful fallback when decoding yields nothing.
    static let empty = InsightResult(topic: "", suggestions: [], answer: nil,
                                     todos: [], decisions: [])

    init(topic: String, suggestions: [String], answer: String?,
         todos: [InsightTodo], decisions: [String]) {
        self.topic = topic
        self.suggestions = suggestions
        self.answer = answer
        self.todos = todos
        self.decisions = decisions
    }

    /// Decode the same required fields declared by `responseSchema`. `answer` may be
    /// explicitly null, but omitting it is a contract violation.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = try c.decode(String.self, forKey: .topic)
        suggestions = try c.decode([String].self, forKey: .suggestions)
        guard suggestions.count <= 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .suggestions,
                in: c,
                debugDescription: "suggestions exceeds the schema maximum of 3"
            )
        }
        guard c.contains(.answer) else {
            throw DecodingError.keyNotFound(
                CodingKeys.answer,
                .init(codingPath: c.codingPath, debugDescription: "answer is required")
            )
        }
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        todos = try c.decode([InsightTodo].self, forKey: .todos)
        decisions = try c.decode([String].self, forKey: .decisions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(topic, forKey: .topic)
        try container.encode(suggestions, forKey: .suggestions)
        if let answer {
            try container.encode(answer, forKey: .answer)
        } else {
            try container.encodeNil(forKey: .answer)
        }
        try container.encode(todos, forKey: .todos)
        try container.encode(decisions, forKey: .decisions)
    }

    private enum CodingKeys: String, CodingKey {
        case topic, suggestions, answer, todos, decisions
    }

    /// True when there's genuinely nothing to show (used to keep the cards' empty
    /// state honest rather than rendering blank boxes).
    var isEmpty: Bool {
        topic.trimmed.isEmpty && suggestions.isEmpty && (answer?.trimmed.isEmpty ?? true)
            && todos.isEmpty && decisions.isEmpty
    }
}

/// One action item: who is responsible and what they need to do.
struct InsightTodo: Codable, Equatable, Identifiable {
    /// Stable-enough identity for SwiftUI ForEach (content-derived; these lists are
    /// small and fully replaced on each generation, so a content hash is sufficient).
    var id: String { "\(who)|\(what)" }
    var who: String
    var what: String
}

extension InsightResult {
    static let responseSchema = LLMResponseSchema(
        name: "insight_result",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "topic": .object([
                    "type": .string("string"),
                    "description": .string("Summarize the current topic in one or two English sentences, or return an empty string")
                ]),
                "suggestions": .object([
                    "type": .string("array"),
                    "description": .string("Suggested next steps or follow-up questions for the user, in English"),
                    "items": .object(["type": .string("string")]),
                    "maxItems": .integer(3)
                ]),
                "answer": .object([
                    "type": .array([.string("string"), .string("null")]),
                    "description": .string("A suggested answer in English if the other participant just asked a question; otherwise null")
                ]),
                "todos": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "who": .object(["type": .string("string")]),
                            "what": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("who"), .string("what")]),
                        "additionalProperties": .bool(false)
                    ])
                ]),
                "decisions": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ])
            ]),
            "required": .array([
                .string("topic"), .string("suggestions"), .string("answer"),
                .string("todos"), .string("decisions")
            ]),
            "additionalProperties": .bool(false)
        ])
    )

    /// Decode from the persisted JSON string on a `MeetingRecord`. Returns nil for
    /// nil/blank/corrupt JSON so callers can treat "no insight yet" and "unreadable"
    /// identically (show the generate button).
    static func decode(from json: String?) -> InsightResult? {
        guard let json, !json.trimmed.isEmpty,
              let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(InsightResult.self, from: data)
        else { return nil }
        return result
    }

    /// Encode to a compact JSON string for persistence. Returns nil on the (practically
    /// impossible) encode failure so the caller just skips saving rather than crashing.
    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
