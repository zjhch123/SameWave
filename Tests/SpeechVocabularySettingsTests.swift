import XCTest
@testable import SameWave

@MainActor
final class SpeechVocabularySettingsTests: XCTestCase {
    func testUsesDefaultVocabularyUntilUserSaves() {
        withIsolatedDefaults { defaults in
            let settings = SpeechVocabularySettings(defaults: defaults)

            XCTAssertEqual(settings.phrases, SpeechVocabularySettings.defaultPhrases)
        }
    }

    func testSaveTrimsDropsEmptyAndDeduplicatesCaseInsensitively() {
        withIsolatedDefaults { defaults in
            let settings = SpeechVocabularySettings(defaults: defaults)
            settings.save([" Claude Code ", "", "claude code", "Kusto"])

            XCTAssertEqual(settings.phrases, ["Claude Code", "Kusto"])
            XCTAssertEqual(
                SpeechVocabularySettings(defaults: defaults).phrases,
                ["Claude Code", "Kusto"]
            )
        }
    }

    func testEmptyVocabularyPersistsWithoutRestoringDefaults() {
        withIsolatedDefaults { defaults in
            SpeechVocabularySettings(defaults: defaults).save([])

            XCTAssertTrue(SpeechVocabularySettings(defaults: defaults).phrases.isEmpty)
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "SpeechVocabularySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
