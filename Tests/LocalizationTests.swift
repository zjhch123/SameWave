import XCTest
@testable import SameWave

@MainActor
final class LocalizationTests: XCTestCase {
    private var isChinese: Bool { Bundle.main.preferredLocalizations.first == "zh-Hans" }

    func testUnexpectedHistoryModelErrorExplainsDataPreservation() {
        XCTAssertEqual(MeetingHistoryStore.StorageError.unexpectedDataModel.localizedDescription, isChinese
            ? "会议数据文件与 SameWave 的数据模型不匹配，文件已保持原样。"
            : "The meeting data file does not match SameWave's data model. The file has been left unchanged.")
    }

    func testInsightPromptUsesActiveAppLanguageForAllGeneratedContent() {
        let language = isChinese ? "Simplified Chinese" : "English"
        XCTAssertTrue(InsightRequest.systemPrompt.contains("Write conclusion, points, and every summary item in \(language)"))
        XCTAssertTrue(InsightRequest.systemPrompt.contains("regardless of the transcript language or language requests in the analysis instructions"))
        XCTAssertTrue(InsightRequest.systemPrompt.contains("Preserve proper names and justified vocabulary spelling"))
        XCTAssertTrue(InsightRequest.systemPrompt.contains("Keep JSON field names exactly as specified"))
        if isChinese { XCTAssertFalse(InsightRequest.systemPrompt.contains("in English")) }
    }

    func testAutomaticManualBatchAndSummaryKeepAppLanguageAndExistingVersions() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        // The meeting language deliberately differs from the app language.
        let pair: MeetingLanguagePair = isChinese ? .englishToEnglish : .simplifiedChineseToSimplifiedChinese
        let record = try history.createDraft(languagePair: pair)
        try history.beginCapture(record, languagePair: pair)
        let definition = try XCTUnwrap(record.definitions.first)
        definition.automaticallyUpdates = true
        let earlier = Phase2Fixture.snapshot(record: record, configuration: definition.configuration, kind: .manual)
        try history.appendInsight(earlier)
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let engine = InsightEngine(settings: AISettings(defaults: defaults), history: history, providerFactory: { provider })
        let now = Date(timeIntervalSince1970: 1_000)
        let text = isChinese ? "XPay launch requires security review. " : "XPay 发布前需要完成安全审核。"
        var section = Section(id: 1, speaker: .remote)
        section.committedSource = [String(repeating: text, count: 10)]
        let sources = InsightSource.capture([section], includingProvisional: false)
        let conclusion = isChinese ? "XPay 发布前需要完成安全审核。" : "XPay launch requires security review."
        let point = isChinese ? "确认审核负责人。" : "Confirm the review owner."
        let summary = MeetingSummary(topics: [conclusion], decisions: [], actionItems: [point], openQuestions: [], suggestions: [])

        func complete(_ index: Int, withSummary: Bool) async throws {
            try await Phase2Fixture.waitUntil { await provider.count == index + 1 }
            try await provider.succeed(index, conclusion: conclusion,
                points: withSummary ? [] : [point], summary: withSummary ? summary : nil)
            try await Phase2Fixture.waitUntil { record.insightSnapshots.count == index + 2 }
        }

        engine.startRecording(record, sections: [], now: now)
        engine.automaticTick(record: record, sections: [section], vocabulary: ["XPay"], elapsedSeconds: 46,
                             now: now.addingTimeInterval(46))
        try await complete(0, withSummary: true)
        engine.generate(record: record, configuration: definition.configuration, kind: .manual,
                        sources: sources, vocabulary: ["XPay"], elapsedSeconds: 47)
        try await complete(1, withSummary: false)
        engine.generateAll(record: record, sources: sources, vocabulary: ["XPay"], elapsedSeconds: 48)
        try await complete(2, withSummary: false)
        engine.stopRecording(record.id)
        try history.finish(record, sections: [section], endedAt: .now)
        engine.generate(record: record, configuration: .summary, kind: .summary,
                        sources: sources, vocabulary: ["XPay"], elapsedSeconds: 49)
        try await complete(3, withSummary: true)

        let systems = await provider.systems
        XCTAssertEqual(systems, Array(repeating: InsightRequest.systemPrompt, count: 4))
        let requests = try await provider.users.map { try JSONDecoder().decode(InsightInput.self, from: Data($0.utf8)) }
        XCTAssertEqual(requests.map(\.kind), [.automatic, .manual, .manual, .summary])
        XCTAssertTrue(requests.allSatisfy { $0.sources == sources && $0.vocabulary == ["XPay"] })
        let saved = try record.insightSnapshots.map { try $0.decoded() }
        XCTAssertTrue(saved.contains(earlier))
        for value in saved where value.id != earlier.id {
            XCTAssertEqual(value.result.conclusion, conclusion)
            if let parts = value.result.summary { XCTAssertEqual(parts, summary) }
            else { XCTAssertEqual(value.result.points, [point]) }
        }
        XCTAssertEqual(record.languagePair, pair)
        let markdown = TranscriptExporter.markdown(record: record)
        XCTAssertTrue(markdown.contains(earlier.result.conclusion))
        XCTAssertTrue(markdown.contains(conclusion))
        XCTAssertTrue(markdown.contains(point))
        XCTAssertTrue(markdown.contains("#### Action Items"))
    }

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
