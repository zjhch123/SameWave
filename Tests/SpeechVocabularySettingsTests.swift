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

    func testImportSavesOnlyNewWordsAndKeepsManualEditsPending() {
        withIsolatedDefaults { defaults in
            let settings = SpeechVocabularySettings(defaults: defaults)
            settings.save(["XPay", "Removed"])
            let draft = SpeechVocabularyDraft(settings: settings)
            draft.text = " XPay\nManual addition\n\n"

            let added = draft.saveImported(["xpay", "M365 Copilot", "Removed", "Manual addition"])

            XCTAssertEqual(added, 1)
            XCTAssertEqual(draft.text, " XPay\nManual addition\n\nM365 Copilot")
            XCTAssertTrue(draft.isDirty)
            XCTAssertEqual(settings.phrases, ["XPay", "Removed", "M365 Copilot"])

            draft.revert()

            XCTAssertFalse(draft.isDirty)
            XCTAssertEqual(draft.phrases, ["XPay", "Removed", "M365 Copilot"])
            XCTAssertEqual(SpeechVocabularySettings(defaults: defaults).phrases, settings.phrases)
        }
    }

    func testCancelledInitialFileSelectionDoesNotStartImportWindowWorkflow() {
        withIsolatedDefaults { defaults in
            let settings = SpeechVocabularySettings(defaults: defaults)
            let controller = VocabularyImportController(
                aiSettings: AISettings(),
                vocabularyDraft: SpeechVocabularyDraft(settings: settings)
            )
            let cancellation = NSError(
                domain: NSCocoaErrorDomain,
                code: NSUserCancelledError
            )

            let shouldOpenWindow = controller.handleFileSelection(.failure(cancellation))

            XCTAssertFalse(shouldOpenWindow)
            XCTAssertEqual(controller.state, .idle)
        }
    }

    func testClosingImportClearsWindowWorkflowState() {
        withIsolatedDefaults { defaults in
            let settings = SpeechVocabularySettings(defaults: defaults)
            let controller = VocabularyImportController(
                aiSettings: AISettings(),
                vocabularyDraft: SpeechVocabularyDraft(settings: settings)
            )
            let pickerError = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
            XCTAssertTrue(controller.handleFileSelection(.failure(pickerError)))
            XCTAssertNotEqual(controller.state, .idle)

            controller.close()

            XCTAssertEqual(controller.state, .idle)
            XCTAssertTrue(controller.candidates.isEmpty)
        }
    }

    func testImportIntoCleanDraftRemainsCleanAndDeduplicatesAtSaveTime() {
        withIsolatedDefaults { defaults in
            let settings = SpeechVocabularySettings(defaults: defaults)
            settings.save(["XPay"])
            let draft = SpeechVocabularyDraft(settings: settings)
            XCTAssertEqual(draft.saveImported(["New", " new "]), 1)
            XCTAssertFalse(draft.isDirty)
            XCTAssertEqual(draft.saveImported(["NEW"]), 0)
            XCTAssertEqual(settings.phrases, ["XPay", "New"])
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "SpeechVocabularySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
