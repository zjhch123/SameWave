import Foundation
import Observation

enum AppLanguage: String {
    case system
    case english = "en"
    case chinese = "zh-Hans"
}

/// Uses the native per-app preference so every localization boundary agrees at launch.
@MainActor
@Observable
final class AppLanguageSettings {
    private let defaults: UserDefaults

    var language: AppLanguage {
        didSet {
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    init(suiteName: String? = nil) {
        defaults = UserDefaults(suiteName: suiteName)!
        let domainName = suiteName ?? Bundle.main.bundleIdentifier!
        // A normal defaults lookup also inherits global languages. Only an app-domain
        // override means the user chose a language instead of following the system.
        let override = defaults.persistentDomain(forName: domainName)?["AppleLanguages"] as? [String]
        if let override, !override.isEmpty {
            let preferred = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: override)
            language = preferred.first == "zh-Hans" ? .chinese : .english
        } else {
            language = .system
        }
    }
}
