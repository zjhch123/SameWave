import Foundation
import Observation

@MainActor
@Observable
final class DefaultInsightSettings {
    private(set) var templates: [InsightTemplate] = []
    private(set) var loadError: String?
    private let defaults: UserDefaults
    static let storageKey = "insights.defaultTemplates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard defaults.object(forKey: Self.storageKey) != nil else {
            templates = InsightTemplate.initialDefaults
            return
        }
        do {
            guard let data = defaults.data(forKey: Self.storageKey) else { throw SettingsError.invalidTemplates }
            let saved = try JSONDecoder().decode([InsightTemplate].self, from: data)
            try Self.validate(saved)
            templates = saved
        } catch {
            loadError = String(localized: "Could not read default insights: \(error.localizedDescription)")
        }
    }

    func templatesForNewMeeting() throws -> [InsightTemplate] {
        if let loadError { throw SettingsError.unreadable(loadError) }
        return templates
    }

    func save(_ template: InsightTemplate) throws {
        var updated = try templatesForNewMeeting()
        if let index = updated.firstIndex(where: { $0.id == template.id }) {
            updated[index] = template.normalized
        } else {
            updated.append(template.normalized)
        }
        try persist(updated)
    }

    func remove(id: UUID) throws {
        try persist(templatesForNewMeeting().filter { $0.id != id })
    }

    /// Explicit recovery only; unreadable saved content is never overwritten on load.
    func reset() throws {
        try persist(InsightTemplate.initialDefaults)
    }

    private func persist(_ templates: [InsightTemplate]) throws {
        try Self.validate(templates)
        let data = try JSONEncoder().encode(templates)
        defaults.set(data, forKey: Self.storageKey)
        self.templates = templates
        loadError = nil
    }

    private static func validate(_ templates: [InsightTemplate]) throws {
        guard templates.allSatisfy(\.isValid), Set(templates.map(\.id)).count == templates.count else {
            throw SettingsError.invalidTemplates
        }
    }

    enum SettingsError: LocalizedError {
        case invalidTemplates
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .invalidTemplates: String(localized: "Default insights contain invalid or duplicate entries.")
            case .unreadable(let message): message
            }
        }
    }
}
