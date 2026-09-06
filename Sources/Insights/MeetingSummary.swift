import Foundation

/// The summary's named parts share one request, cutoff, and immutable history version.
struct MeetingSummary: Codable, Equatable, Sendable {
    let topics: [String]
    let decisions: [String]
    let actionItems: [String]
    let openQuestions: [String]
    let suggestions: [String]

    static let empty = MeetingSummary(topics: [], decisions: [], actionItems: [], openQuestions: [], suggestions: [])

    struct Part: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let items: [String]
        let emptyMessage: String
    }

    var parts: [Part] {
        [
            Part(id: "topics", title: "Topics", symbol: "text.magnifyingglass", items: topics,
                 emptyMessage: "No additional topics recorded."),
            Part(id: "suggestions", title: "Suggestions", symbol: "lightbulb", items: suggestions,
                 emptyMessage: "No further suggestions."),
            Part(id: "actionItems", title: "Action Items", symbol: "checklist", items: actionItems,
                 emptyMessage: "No action items assigned."),
            Part(id: "decisions", title: "Decisions", symbol: "checkmark.seal", items: decisions,
                 emptyMessage: "No decisions recorded."),
            Part(id: "openQuestions", title: "Open Questions", symbol: "questionmark.bubble", items: openQuestions,
                 emptyMessage: "No unresolved questions recorded.")
        ]
    }

    var isValid: Bool {
        parts.allSatisfy { part in
            part.items.count <= 8 && part.items.allSatisfy { !$0.trimmed.isEmpty && $0.count <= 500 }
        }
    }

    static let schema = JSONValue.object([
        "type": .string("object"),
        "properties": .object(Dictionary(uniqueKeysWithValues:
            ["topics", "decisions", "actionItems", "openQuestions", "suggestions"].map { key in
                (key, .object([
                    "type": .string("array"), "maxItems": .integer(8),
                    "items": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(500)])
                ]))
            }
        )),
        "required": .array(["topics", "decisions", "actionItems", "openQuestions", "suggestions"].map(JSONValue.string)),
        "additionalProperties": .bool(false)
    ])
}
