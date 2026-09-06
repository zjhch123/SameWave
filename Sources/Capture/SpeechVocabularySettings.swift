import Foundation
import Observation

@MainActor
@Observable
final class SpeechVocabularySettings {
    static let defaultPhrases = [
        "claude code",
        "Bestla",
        "ODB",
        "FileItem",
        "bootstrap",
        "Arbutus",
        "XPay",
        "Wallet",
        "Copilot",
        "M365 Copilot",
        "One Copilot",
        "OneCopilotMobile",
        "OCM",
        "Unified Copilot",
        "Unified App Experience",
        "ExP",
        "Scorecard",
        "ECS",
        "ADO",
        "Kusto",
        "Intune",
        "Entra",
        "GlobalProtect",
        "PR",
        "SKU",
        "AAD",
        "MSAL",
        "OBO",
        "UPN",
        "1JS",
        "SSR",
        "SSE",
        "SAW",
        "RAI",
        "CELA",
        "MSAI",
        "Yujie Liu",
        "Shixin Cai",
        "Jessica Zhang",
        "Baogui Yan",
        "Lei Bian",
    ]

    private(set) var phrases: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.stringArray(forKey: Keys.phrases) {
            phrases = Self.normalized(saved)
        } else {
            phrases = Self.defaultPhrases
        }
    }

    func save(_ phrases: [String]) {
        let normalized = Self.normalized(phrases)
        self.phrases = normalized
        defaults.set(normalized, forKey: Keys.phrases)
    }

    nonisolated static func phrases(from text: String) -> [String] {
        normalized(text.components(separatedBy: .newlines))
    }

    nonisolated static func normalized(_ phrases: [String]) -> [String] {
        var seen: Set<String> = []
        return phrases.compactMap { rawPhrase in
            let phrase = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { return nil }
            guard seen.insert(identity(phrase)).inserted else { return nil }
            return phrase
        }
    }

    nonisolated static func identity(_ phrase: String) -> String {
        phrase.trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated static func newPhrases(from phrases: [String], excluding existing: [String]) -> [String] {
        let identities = Set(existing.map(identity))
        return normalized(phrases).filter { !identities.contains(identity($0)) }
    }

    private enum Keys {
        static let phrases = "speech.vocabulary.phrases"
    }
}
