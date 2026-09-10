import Foundation

/// Editable content copied into a meeting, without shared persistence identity.
struct InsightTemplate: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title = ""
    var prompt = ""
    var automaticallyUpdates = false
    var scope: InsightScope = .cumulative

    var isValid: Bool { !title.trimmed.isEmpty && !prompt.trimmed.isEmpty }

    var normalized: Self {
        var value = self
        value.title = title.trimmed
        value.prompt = prompt.trimmed
        return value
    }

    static var initialDefaults: [Self] {
        [Self(
            title: String(localized: "Meeting Overview"),
            prompt: "Give a broad, structured meeting overview with key topics, suggestions, action items, decisions, and open questions. Return the summary parts, not a flat list of points. Track commitments and any later changes."
        )]
    }
}

extension InsightDefinition {
    var template: InsightTemplate {
        InsightTemplate(id: id, title: title, prompt: prompt,
                        automaticallyUpdates: automaticallyUpdates, scope: configuration.scope)
    }
}
