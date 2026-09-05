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
            let identity = phrase.lowercased(with: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(identity).inserted else { return nil }
            return phrase
        }
    }

    private enum Keys {
        static let phrases = "speech.vocabulary.phrases"
    }
}

@MainActor
@Observable
final class SpeechVocabularyDraft {
    var text: String

    private let settings: SpeechVocabularySettings

    init(settings: SpeechVocabularySettings) {
        self.settings = settings
        text = settings.phrases.joined(separator: "\n")
    }

    var phrases: [String] {
        SpeechVocabularySettings.phrases(from: text)
    }

    var isDirty: Bool {
        phrases != settings.phrases
    }

    var existingPhrases: [String] {
        SpeechVocabularySettings.normalized(settings.phrases + phrases)
    }

    @discardableResult
    func saveImported(_ phrases: [String]) -> Int {
        let additions = VocabularyCandidateReview.newPhrases(from: phrases, excluding: existingPhrases)
        guard !additions.isEmpty else { return 0 }
        settings.save(settings.phrases + additions)
        // Append without rewriting the manual draft: pending deletions, edits and
        // whitespace remain untouched, and cancelling Settings cannot undo this save.
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += additions.joined(separator: "\n")
        return additions.count
    }

    func save() {
        settings.save(phrases)
        text = settings.phrases.joined(separator: "\n")
    }

    func revert() {
        text = settings.phrases.joined(separator: "\n")
    }
}
