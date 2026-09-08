import XCTest
@testable import SameWave

@MainActor
final class AppLanguageSettingsTests: XCTestCase {
    func testDefaultFollowsSystemWithoutPersistingInheritedLanguages() {
        let (domain, defaults) = preferences()
        XCTAssertEqual(AppLanguageSettings(suiteName: domain).language, .system)
        XCTAssertNil(defaults.persistentDomain(forName: domain)?["AppleLanguages"])
    }

    func testExplicitLanguagePersistsAcrossSettingsInstancesWithoutChangingOtherPreferences() {
        let (domain, defaults) = preferences()
        defaults.set("Saved preference", forKey: "Unrelated")
        let globalLanguages = defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        let settings = AppLanguageSettings(suiteName: domain)
        for language in [AppLanguage.english, .chinese] {
            settings.language = language
            XCTAssertEqual(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String], [language.rawValue])
            XCTAssertEqual(AppLanguageSettings(suiteName: domain).language, language)
            XCTAssertEqual(defaults.string(forKey: "Unrelated"), "Saved preference")
            XCTAssertEqual(defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String], globalLanguages)
        }
    }

    func testReturningToSystemRemovesOverrideInsteadOfCopyingCurrentSystemLanguage() {
        let (domain, defaults) = preferences()
        let settings = AppLanguageSettings(suiteName: domain)
        for language in [AppLanguage.chinese, .english] {
            settings.language = language
            settings.language = .system
            XCTAssertNil(defaults.persistentDomain(forName: domain)?["AppleLanguages"])
            XCTAssertEqual(AppLanguageSettings(suiteName: domain).language, .system)
        }
    }

    func testExistingMacOSAppPreferenceUsesNativeLanguageMatching() {
        let (domain, defaults) = preferences()
        for (languages, expected) in [
            (["en-US"], AppLanguage.english),
            (["zh-Hans-CN", "en"], .chinese),
            (["fr", "zh-Hans"], .chinese),
            ([], .system)
        ] {
            defaults.set(languages, forKey: "AppleLanguages")
            XCTAssertEqual(AppLanguageSettings(suiteName: domain).language, expected)
            XCTAssertEqual(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String], languages)
        }
    }

    private func preferences() -> (String, UserDefaults) {
        let domain = "AppLanguageSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        addTeardownBlock { defaults.removePersistentDomain(forName: domain) }
        return (domain, defaults)
    }
}
