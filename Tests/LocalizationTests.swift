import XCTest
@testable import SameWave

@MainActor
final class LocalizationTests: XCTestCase {
    private var isChinese: Bool { Bundle.main.preferredLocalizations.first == "zh-Hans" }

    func testCompiledCatalogsAndUnsupportedLanguageSelection() throws {
        for (language, newMeeting, speechPermission) in [
            ("en", "New Meeting", "SameWave uses on-device speech recognition"),
            ("zh-Hans", "新建会议", "SameWave 使用设备端语音识别")
        ] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "New Meeting", value: nil, table: nil), newMeeting)
            let permission = bundle.localizedString(forKey: "NSSpeechRecognitionUsageDescription", value: nil, table: "InfoPlist")
            XCTAssertTrue(permission.contains(speechPermission))
        }
        XCTAssertEqual(Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: ["fr"]).first, "en")
    }

    func testHistoryCountsUseTheSelectedLanguageAndEnglishSingular() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.endedAt = record.startedAt.addingTimeInterval(65)
        for count in [0, 1, 2] {
            record.lineCount = count
            let expected = isChinese ? "\(count) 段 · 1 分 5 秒"
                : "\(count) \(count == 1 ? "section" : "sections") · 1m 5s"
            XCTAssertEqual(record.metaText, expected)
        }
    }

    func testVocabularyFeedbackResolvesTwoIndependentPluralCounts() {
        let defaults = Phase2Fixture.defaults(self)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        vocabulary.save(["Existing"])
        let editor = VocabularyEditorStore(aiSettings: AISettings(defaults: defaults), settings: vocabulary)
        for (text, english, chinese) in [
            ("First", "Added 1 term", "已添加 1 个术语"),
            ("Second\nExisting", "Added 1 term · Skipped 1 duplicate", "已添加 1 个术语 · 跳过 1 个重复项"),
            ("Third\nFourth\nExisting", "Added 2 terms · Skipped 1 duplicate", "已添加 2 个术语 · 跳过 1 个重复项"),
            ("Fifth\nFirst\nSecond", "Added 1 term · Skipped 2 duplicates", "已添加 1 个术语 · 跳过 2 个重复项")
        ] {
            editor.manualText = text
            editor.addTerms()
            XCTAssertEqual(editor.vocabularyMessage, isChinese ? chinese : english)
        }
    }

    func testErrorsTranslateTheirWrapperAndPreserveDiagnosticDetails() {
        XCTAssertEqual(LLMError.network("raw diagnostic").localizedDescription,
                       isChinese ? "网络请求失败：raw diagnostic" : "Network request failed: raw diagnostic")
        XCTAssertEqual(MeetingLanguage.simplifiedChinese.localizedLabel, isChinese ? "简体中文" : "Simplified Chinese")
        XCTAssertEqual(MeetingLanguage.simplifiedChinese.label, "Simplified Chinese")
        XCTAssertEqual(MeetingLanguage.english.localeID, "en-US")
    }

    func testMeetingContentAndExportStayIndependentOfInterfaceLanguage() throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.userTitle = "New Meeting"
        var section = Section(id: 0, speaker: .mine)
        section.committedSource = ["Settings"]
        section.targetText = "Settings"
        try history.finish(record, sections: [section], endedAt: record.startedAt.addingTimeInterval(65))
        let value = InsightSnapshotValue(id: UUID(), input: Phase2Fixture.input(record: record), completedAt: .now,
            result: InsightResult(conclusion: "User content", points: [], summary: .empty))
        try history.appendInsight(value)
        XCTAssertEqual(record.displayTitle, "New Meeting")
        XCTAssertEqual(record.lines.first?.sourceText, "Settings")
        XCTAssertEqual(try record.insightSnapshots.first?.decoded(), value)
        let markdown = TranscriptExporter.markdown(record: record)
        XCTAssertTrue(markdown.contains("# Meeting Transcript"))
        XCTAssertTrue(markdown.contains("#### Action Items"))
        XCTAssertTrue(markdown.contains("No action items assigned."))
        XCTAssertTrue(markdown.contains("Me:** Settings"))
        XCTAssertTrue(markdown.contains("1m 5s"))
        XCTAssertFalse(markdown.contains("行动项"))
    }
}
