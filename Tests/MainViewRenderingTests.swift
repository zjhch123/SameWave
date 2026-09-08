import AppKit
import SwiftData
import SwiftUI
import Vision
import XCTest
@testable import SameWave

@MainActor
final class MainViewRenderingTests: XCTestCase {
    func testLocalizedPreparationSheetAlignsTitleAndDone() async throws {
        let chinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let settings = AISettings(defaults: defaults)
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let title = chinese ? "会议准备" : "Meeting Preparation"
        let done = chinese ? "完成" : "Done"
        let view = MeetingPreparationView(record: record, history: history,
            editor: coordinator.vocabularyEditor(for: record, settings: settings), onDone: {})
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
        try await render(view, size: NSSize(width: 620, height: 640),
            name: "preparation-sheet-aligned-\(chinese ? "zh-Hans" : "en")",
            expectedLabels: [title, done], alignedLabels: (title, done))
    }

    func testLocalizedAISettingsShowMasterSwitchAndCompactHelp() async throws {
        let chinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        navigation.selectedTab = .ai
        for enabled in [true, false] {
            settings.isEnabled = enabled
            try await render(SettingsView().environment(navigation), size: NSSize(width: 600, height: 540),
                name: "compact-ai-settings-\(enabled)-\(chinese ? "zh-Hans" : "en")",
                expectedLabels: chinese ? ["启用", "服务", "立即生效", "测试连接", "保存"]
                    : ["Enable", "Services", "Applies immediately", "Test Connection", "Save"],
                absentLabels: ["Audio is never uploaded", "One configuration for insights"])
        }
    }

    func testLocalizedGeneratedInsightContent() async throws {
        let chinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let suffix = chinese ? "zh-Hans" : "en"
        let conclusion = chinese ? "发布前完成审核。" : "Complete review before launch."
        let point = chinese ? "确认审核负责人。" : "Confirm the review owner."
        let labels = chinese ? ["发布前完成审核", "确认审核负责人"] : ["Complete review before launch", "Confirm the review owner"]
        let history = try Phase2Fixture.history()
        let defaults = Phase2Fixture.defaults(self)
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let configuration = InsightConfiguration(id: UUID(), title: "Launch Risks", prompt: "Identify risks", scope: .cumulative)
        let value = InsightSnapshotValue(id: UUID(), input: Phase2Fixture.input(record: record, configuration: configuration, kind: .manual),
            completedAt: .now, result: InsightResult(conclusion: conclusion, points: [point]))
        try history.appendInsight(value)
        try await render(InsightResultCard(meetingID: record.id, configuration: configuration, snapshots: record.insightSnapshots)
            .defaultAppStorage(defaults), size: NSSize(width: 240, height: 340), name: "localized-generated-insight-\(suffix)",
            expectedLabels: labels)
        let summary = MeetingSummary(topics: [conclusion], decisions: [], actionItems: [point], openQuestions: [], suggestions: [])
        try await render(MeetingSummaryCards(summary: summary), size: NSSize(width: 240, height: 820),
            name: "localized-generated-summary-\(suffix)", expectedLabels: labels)
    }

    func testLocalizedGeneralLanguageChoices() async throws {
        let chinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let suffix = chinese ? "zh-Hans" : "en"
        let domain = "LanguageRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let aiSettings = AISettings(defaults: defaults)
        let languageSettings = AppLanguageSettings(suiteName: domain)
        let navigation = SettingsNavigation(aiSettings: aiSettings, vocabularyEditor:
            VocabularyEditorStore(aiSettings: aiSettings, settings: SpeechVocabularySettings(defaults: defaults)),
            languageSettings: languageSettings)
        XCTAssertEqual(navigation.selectedTab, .general)
        for (language, english, translated) in [
            (AppLanguage.system, "Follow System", "跟随系统"),
            (.english, "English", "英文"),
            (.chinese, "Chinese", "中文")
        ] {
            languageSettings.language = language
            try await render(SettingsView().environment(navigation), size: NSSize(width: 600, height: 540),
                name: "localized-general-\(language.rawValue)-\(suffix)",
                expectedLabels: chinese ? ["通用", "应用语言", translated, "退出并重新打开 SameWave", "完成"]
                    : ["General", "App Language", english, "Quit and reopen SameWave", "Done"])
        }
    }

    func testLocalizedWorkspaceSettingsVocabularyAndSummary() async throws {
        let chinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let suffix = chinese ? "zh-Hans" : "en"
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let settings = AISettings(defaults: defaults)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        let coordinator = CaptureCoordinator(speechVocabularySettings: vocabulary, defaults: defaults)
        coordinator.history = history
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.userTitle = "Settings"
        await coordinator.loadSession(record)
        try await render(MainView(coordinator: coordinator).defaultAppStorage(defaults).environment(settings).environment(navigation)
            .modelContainer(history.container), size: NSSize(width: 940, height: 480), name: "localized-workspace-\(suffix)",
            expectedLabels: chinese ? ["会议准备", "新建会议", "Settings"] : ["Meeting Preparation", "New Meeting", "Settings"])
        navigation.selectedTab = .ai
        try await render(SettingsView().environment(navigation), size: NSSize(width: 600, height: 540),
            name: "localized-settings-\(suffix)", expectedLabels: chinese ? ["设置", "词汇", "连接"] : ["Settings", "Connection", "Vocabulary"])
        try await render(VocabularyEditorView(editor: navigation.vocabularyEditor).environment(navigation),
            size: NSSize(width: 600, height: 540), name: "localized-vocabulary-\(suffix)",
            expectedLabels: chinese ? ["个人词汇", "已保存的词汇"] : ["Personal Vocabulary", "Saved Vocabulary"])
        try await render(MeetingSummaryCards(summary: .empty), size: NSSize(width: 240, height: 820),
            name: "localized-summary-\(suffix)", expectedLabels: chinese ? ["议题", "行动项", "决策", "待解决问题"] : ["Topics", "Action Items", "Decisions", "Open Questions"])
        try await render(InsightDefinitionEditor(record: record, history: history, definition: nil).environment(navigation),
            size: NSSize(width: 500, height: 440), name: "localized-insight-editor-\(suffix)",
            expectedLabels: chinese ? ["添加洞察", "分析重点", "保存"] : ["Add Insight", "Focus", "Save"])
    }

    func testChronologicalCaptionsShowSourceAndTranslationWithoutBusyText() async throws {
        let store = CaptionStore()
        store.updateSource("The release is ready", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("I have a question", speaker: .mine, isFinal: false)
        store.updateSource("The release is ready for review", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.sections.map(\.sourceText), ["The release is ready", "I have a question", "for review"])
        for section in store.sections { XCTAssertNotNil(store.beginTranslation(id: section.id)) }
        try await render(CaptionsView(store: store, isListening: true),
            size: NSSize(width: 700, height: 500), name: "chronological-captions-pending",
            expectedLabels: ["Speaker", "You", "The release is ready", "I have a question", "for review"],
            absentLabels: ["Translating"])
        store.applyTranslation("Ready to release", id: 0, generation: store.sections[0].generation)
        try await render(CaptionsView(store: store, isListening: true),
            size: NSSize(width: 700, height: 500), name: "chronological-captions-complete",
            expectedLabels: ["Ready to release", "The release is ready", "I have a question", "for review"],
            absentLabels: ["Translating"])
        store.updateSource("The release was ready for review", speaker: .remote, isFinal: false)
        XCTAssertNotNil(store.beginTranslation(id: 0))
        try await render(CaptionsView(store: store, isListening: true),
            size: NSSize(width: 700, height: 500), name: "chronological-captions-progress",
            expectedLabels: ["Ready to release", "The release was ready", "I have a question", "for review"],
            absentLabels: ["Translating"])
        store.failTranslation(id: 0, generation: store.sections[0].generation)
        try await render(CaptionsView(store: store, isListening: true),
            size: NSSize(width: 700, height: 500), name: "chronological-captions-failure",
            expectedLabels: ["Translation failed", "The release was ready", "I have a question", "for review"],
            absentLabels: ["Translating", "Ready to release"])
    }

    func testBackgroundRefinementRemainsVisibleWhileAnotherMeetingIsSelected() async throws {
        let history = try Phase2Fixture.history()
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let first = try history.createDraft(languagePair: .englishToEnglish)
        first.userTitle = "Release Planning"
        var section = Section(id: 0, speaker: .remote)
        section.committedSource = ["Review the release plan."]
        try history.finish(first, sections: [section], endedAt: .now)
        let second = try history.createDraft(languagePair: .englishToEnglish)
        second.userTitle = "Design Review"
        try history.finish(second, sections: [section], endedAt: .now)
        let provider = ControlledRefinementProvider()
        addTeardownBlock { await provider.failAll() }
        let refinement = try XCTUnwrap(coordinator.refinement(for: first, settings: settings, providerFactory: { provider }))
        refinement.start()
        await coordinator.openHistory(second)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        XCTAssertEqual(coordinator.backgroundActivity(for: first.id), "Refining transcript")
        XCTAssertNil(coordinator.backgroundActivity(for: second.id))
        try await render(MainView(coordinator: coordinator)
            .environment(settings)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
            .modelContainer(history.container), size: NSSize(width: 940, height: 480), name: "background-refinement-switch",
            expectedLabels: ["Release Planning", "Design Review", "Review the", "release plan."])
        await coordinator.openHistory(first)
        try await render(MainView(coordinator: coordinator)
            .environment(settings)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
            .modelContainer(history.container), size: NSSize(width: 1120, height: 760), name: "background-refinement-return",
            expectedLabels: ["Release Planning", "Review the release plan."])
    }

    func testUserNamedHistoryKeepsItsDateInSidebar() async throws {
        let history = try Phase2Fixture.history()
        let defaults = Phase2Fixture.defaults(self)
        let record = try history.createDraft(languagePair: .englishToEnglish, now: Date(timeIntervalSince1970: 1_000))
        record.userTitle = "User named meeting"
        try history.finish(record, sections: [], endedAt: record.startedAt)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        coordinator.selectedHistoryRecord = record
        try await render(MeetingSidebar(coordinator: coordinator, selectedRecord: .constant(record))
            .modelContainer(history.container), size: NSSize(width: 240, height: 400), name: "v2-user-title-sidebar",
            expectedLabels: ["User named meeting", record.displayDate])
    }

    func testMixedSavedAndUnsavedInsightShapesKeepBothVersionsReadable() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let config = record.definitions[0].configuration
        let input = Phase2Fixture.input(record: record, configuration: config, kind: .manual)
        let focused = InsightSnapshotValue(id: UUID(), input: input, completedAt: .now,
            result: .init(conclusion: "Focused release conclusion", points: ["Retain the rollback checklist."]))
        let structured = InsightSnapshotValue(id: UUID(), input: input, completedAt: .now,
            result: .init(conclusion: "Structured release overview", points: [], summary: Phase2Fixture.summary))
        for (saved, unsaved, name) in [(focused, structured, "focused-history"), (structured, focused, "focused-unsaved")] {
            try await render(InsightResultCard(meetingID: record.id, configuration: config,
                snapshots: [try InsightSnapshot(saved)], unsaved: [unsaved]),
                size: NSSize(width: 360, height: 1_150), name: "v2-mixed-insights-\(name)",
                expectedLabels: ["Focused release conclusion", "Retain the rollback checklist.", "Security review", "Retry Save"],
                absentLabels: ["No content yet."])
        }
    }

    func testPreparationVocabularyPreviewWrapsTwelveTermsAtRegularAndNarrowWidths() async throws {
        let history = try Phase2Fixture.history()
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let phrases = ["ApcPrivateToPublic", "AscPublicToPrivate", "AscSharedItemProcessorP1",
                       "CrawlStateEvent", "CreateGrainTask", "CreateMoveToDeadLetterQueueResponse",
                       "DeadLetterItemDynamicCrawler", "DocProcessor", "EventHub", "GraphAPI",
                       "ItemProcessor", "MailboxSync"] + (1...18).map { "Remaining term \($0)" }
        try history.replaceVocabulary(phrases, in: record)
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: settings,
            readPhrases: { record.confirmedVocabulary },
            replacePhrases: { try history.replaceVocabulary($0, in: record) })
        let view = MeetingPreparationView(record: record, history: history, editor: editor)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
        for width in [600.0, 400.0] {
            try await render(view, size: NSSize(width: width, height: 920),
                name: "preparation-vocabulary-preview-\(Int(width))",
                expectedLabels: ["30 saved terms", "CrawlStateEvent", "MailboxSync", "+18"],
                absentLabels: ["Remaining term", "+27"])
        }
    }

    func testMeetingVocabularyListsAllContextFilesWithoutDocumentControlsOrPreviews() async throws {
        let history = try Phase2Fixture.history()
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let names = ["release-plan.md", "technical-notes.md", "project-roadmap.md",
                     "security-review.md", "meeting-agenda.md", "deployment-guide.md"]
        try history.attach(names.map { .init(fileName: $0, content: String(repeating: "Private document body. ", count: 100)) }, to: record)
        for document in record.documents {
            document.importedAt = Date(timeIntervalSince1970: Double(try XCTUnwrap(names.firstIndex(of: document.fileName))))
        }
        XCTAssertEqual(record.orderedDocuments.map(\.fileName), names)
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: settings,
            readPhrases: { record.confirmedVocabulary },
            replacePhrases: { try history.replaceVocabulary($0, in: record) })
        try await render(MeetingVocabularyView(record: record, editor: editor, manageContext: {})
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults)),
            size: NSSize(width: 600, height: 540), name: "preparation-vocabulary-context-files",
            expectedLabels: names + ["6 documents in Context", "Manage Context", "Extract Vocabulary", "KB"],
            absentLabels: ["Private document body", "Selected files", "Remove", "Choose Markdown"])
    }

    func testPhase2PreparationAndOfflineInsightHistoryRender() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let settings = AISettings(defaults: defaults)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults),
                                             defaults: defaults)
        coordinator.history = history
        coordinator.sourceLanguage = .english
        coordinator.targetLanguage = .english
        await coordinator.startNewMeeting()
        let record = try XCTUnwrap(coordinator.workspaceRecord)
        record.userTitle = "Release Readiness Review"
        try history.attach([.init(fileName: "release-plan.md", content: "XPay requires security review before launch.")], to: record)
        try history.replaceVocabulary(["XPay", "OAuth"], in: record)
        for (index, title) in ["Launch Risks", "Decisions", "Next Steps"].enumerated() {
            let item = InsightDefinition(title: title, prompt: "Analyze \(title)")
            item.createdAt = record.orderedDefinitions[0].createdAt.addingTimeInterval(Double(index + 1))
            item.record = record
            history.context.insert(item)
        }
        try history.save()
        let host = NSHostingView(rootView: MainView(coordinator: coordinator)
            .modelContainer(history.container).environment(settings)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults)).defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await Task.yield()
        try capture(host, name: "Phase 2 preparation")
        try savePNG(host, name: "phase2-preparation")

        window.setContentSize(NSSize(width: 940, height: 480))
        await Task.yield()
        try capture(host, name: "Compact preparation")
        try savePNG(host, name: "phase2-preparation-compact")
        window.setContentSize(NSSize(width: 1120, height: 760))

        var section = Section(id: 1, speaker: .remote)
        section.committedSource = ["Launch Friday, subject to security review."]
        section.targetText = "计划周五发布，但需要先完成安全审核。"
        record.language = MeetingLanguagePair.englishToSimplifiedChinese.rawValue
        try history.finish(record, sections: [section], endedAt: record.startedAt.addingTimeInterval(65))
        let definition = try XCTUnwrap(record.orderedDefinitions.first)
        let template = Phase2Fixture.snapshot(record: record, configuration: definition.configuration, kind: .manual)
        let insight = InsightSnapshotValue(id: template.id, input: template.input, completedAt: template.completedAt,
            result: InsightResult(conclusion: template.result.conclusion,
                points: [], summary: Phase2Fixture.summary))
        try history.appendInsight(insight)
        for item in record.orderedDefinitions where item.id != definition.id {
            try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: item.configuration, kind: .manual))
        }
        try history.appendInsight(Phase2Fixture.snapshot(record: record))
        await coordinator.openHistory(record)
        await Task.yield()
        try capture(host, name: "Phase 2 offline insight history")
        try savePNG(host, name: "phase2-offline-history")
        XCTAssertTrue(try visibleText(host).contains("Custom Insights"))
        XCTAssertFalse(settings.isConfigured)
        XCTAssertEqual(record.insightSnapshots.count, 5)
        window.setContentSize(NSSize(width: 940, height: 480))
        await Task.yield()
        try capture(host, name: "Compact offline insight history")
        try savePNG(host, name: "phase2-insights-compact")

        coordinator.delete(record)
        await Task.yield()
        try capture(host, name: "Empty meetings after deletion")
        try savePNG(host, name: "phase2-empty-meetings")
        XCTAssertNil(coordinator.workspaceRecord)
    }

    func testEnglishMeetingViewsAtMinimumWindowSize() async throws {
        let suite = "SameWaveTests.EnglishUI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: MeetingRecord.self, TranscriptLine.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults),
                                             defaults: defaults)
        // The longest language labels also bypass platform translation during rendering.
        coordinator.sourceLanguage = .simplifiedChinese
        coordinator.targetLanguage = .simplifiedChinese
        let settings = AISettings(defaults: defaults)
        let host = NSHostingView(rootView: MainView(coordinator: coordinator)
            .modelContainer(container)
            .environment(settings)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
            .defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await Task.yield()
        try capture(host, name: "English empty state at minimum window size")

        let record = MeetingRecord(startedAt: .now, endedAt: .now.addingTimeInterval(65),
                                   languagePair: .englishToEnglish, lineCount: 1, status: .ended,
                                   aiTitle: "Product Delivery Timeline and Release Readiness Review",
                                   refinedAt: .now,
                                   lines: [TranscriptLine(speaker: .mine, sourceText: "Review the release plan.",
                                                          targetText: "Review the release plan.", spokenAt: .now,
                                                          orderIndex: 0, sectionId: 0)])
        container.mainContext.insert(record)
        try container.mainContext.save()
        coordinator.selectedHistoryRecord = record
        await Task.yield()
        try capture(host, name: "English history at minimum window size")
    }

    func testSettingsSheetContentKeepsAllTabsAndFixedActionsVisible() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let navigation = Phase2Fixture.settingsNavigation(settings, defaults: defaults)
        for tab in [SettingsNavigation.Tab.general, .ai, .vocabulary] {
            navigation.selectedTab = tab
            let labels: [String]
            switch tab {
            case .general: labels = ["General", "App Language", "Follow System", "Done"]
            case .ai: labels = ["Settings", "Services", "Vocabulary", "Cancel", "Save"]
            case .vocabulary: labels = ["Personal Vocabulary", "Choose Markdown", "Add Terms", "Done"]
            }
            try await render(SettingsView().environment(navigation),
                size: NSSize(width: 600, height: 540), name: "phase2-settings-\(tab)",
                expectedLabels: labels)
        }
    }

    func testInsightEditorsArchiveAndFailureRenderWithoutDetails() async throws {
        let history = try Phase2Fixture.history()
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.attach([.init(fileName: "release-plan.md", content: "XPay requires security review.")], to: record)
        let definition = try XCTUnwrap(record.orderedDefinitions.first)
        let snapshot = Phase2Fixture.snapshot(record: record, configuration: definition.configuration, kind: .manual)
        try history.appendInsight(snapshot)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let editor = coordinator.vocabularyEditor(for: record, settings: settings)
        try await render(MeetingVocabularyView(record: record, editor: editor, manageContext: {})
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults)), size: NSSize(width: 600, height: 540), name: "phase2-vocabulary-management",
            expectedLabels: ["1 document in Context", "release-plan.md", "Meeting Vocabulary", "Add Terms"],
            absentLabels: ["XPay requires security review.", "Remove Attachment", "Review", "Suggested Terms", "Request Details"])
        try await render(InsightDefinitionEditor(record: record, history: history, definition: definition),
                         size: NSSize(width: 500, height: 440), name: "phase2-insight-editor")
        try await render(InsightResultCard(meetingID: record.id, configuration: definition.configuration, snapshots: record.insightSnapshots,
            tone: 1, state: .failed("The AI service is unavailable. Try again."), canGenerate: true, generate: {}),
            size: NSSize(width: 240, height: 360), name: "phase2-insight-failure",
            expectedLabels: ["Launch depends on"], absentLabels: ["Details", "Generate", "Retry"])
        history.context.delete(definition)
        try history.save()
        try await render(ArchivedInsightResults(record: record),
                         size: NSSize(width: 500, height: 440), name: "phase2-archived-insights",
                         expectedLabels: ["Launch depends on"], absentLabels: ["Details"])
    }

    func testMeetingVocabularySuggestionsSaveInlineAndKeepUncheckedTerms() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.userTitle = "XPay integration"
        try history.replaceVocabulary(["SameWave"], in: record)
        let directory = FileManager.default.temporaryDirectory.appending(path: "VocabularyFlow-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let documents = ["release-plan.md", "technical-notes.md"].map {
            VocabularySourceDocument(fileName: $0, content: String(repeating: "XPay ", count: 3_600))
        }
        try history.attach(documents, to: record)
        let urls = try documents.map { document in
            let url = directory.appending(path: document.fileName)
            try document.content.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        var failSave = true
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: settings,
            readPhrases: { record.confirmedVocabulary }, replacePhrases: { phrases in
                if failSave { throw CocoaError(.fileWriteOutOfSpace) }
                try history.replaceVocabulary(phrases, in: record)
            })
        let importer = editor.importer
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["XPay","SwiftData","OAuth"]}"#), .held(#"{"phrases":[]}"#)
        ])
        defer { importer.reset() }
        addTeardownBlock { await provider.release() }
        importer.start(from: urls, using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        let view = MeetingVocabularyView(record: record, editor: editor, manageContext: {})
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
        let size = NSSize(width: 600, height: 540)
        try await render(view, size: size, name: "phase2-vocabulary-extracting",
            expectedLabels: ["documents in Context", "Suggested Terms", "Add to Vocabulary", "Stop", "Done"],
            absentLabels: ["Review", "Request Details", "Source"])
        importer.candidates[0].text = "XPay Pro"
        importer.candidates[2].isSelected = false
        let uncheckedID = importer.candidates[2].id
        importer.saveSelected()
        XCTAssertTrue(importer.isRunning)
        XCTAssertEqual(importer.candidates.count, 3)
        try await render(view, size: size, name: "phase2-vocabulary-save-failure",
            expectedLabels: ["Could not save terms", "Add to Vocabulary", "Done"], absentLabels: ["Review"])
        failSave = false
        importer.saveSelected()
        XCTAssertTrue(importer.isRunning)
        XCTAssertEqual(Set(record.confirmedVocabulary), ["SameWave", "XPay Pro", "SwiftData"])
        XCTAssertEqual(importer.candidates.map(\.id), [uncheckedID])
        XCTAssertFalse(importer.candidates[0].isSelected)
        await provider.release()
        try await Phase2Fixture.waitUntil { !importer.isRunning }
        try await render(view, size: size, name: "phase2-vocabulary-saved-inline",
            expectedLabels: ["Suggested Terms", "OAuth", "Meeting Vocabulary", "New terms saved: 2"],
            absentLabels: ["Review", "Could not save terms", "Request Details"])
        importer.selectAll(true)
        importer.saveSelected()
        try await render(view, size: size, name: "phase2-vocabulary-all-saved",
            expectedLabels: ["Meeting Vocabulary", "Suggested Terms", "New terms saved: 1", "Done"],
            absentLabels: ["Add to Vocabulary", "Review"])
    }

    func testMeetingVocabularyEmptyReadyAndLongListsKeepTheirContextAndActions() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        record.userTitle = "XPay integration"
        let editor = VocabularyEditorStore(scope: .meeting, aiSettings: settings,
            readPhrases: { record.confirmedVocabulary },
            replacePhrases: { try history.replaceVocabulary($0, in: record) })
        let importer = editor.importer
        let view = MeetingVocabularyView(record: record, editor: editor, manageContext: {})
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
        let size = NSSize(width: 600, height: 540)
        try await render(view, size: size, name: "phase2-vocabulary-empty",
            expectedLabels: ["Go to Context", "Meeting Vocabulary", "No saved terms yet.", "Add Terms", "Done"],
            absentLabels: ["Review", "Suggested Terms", "Add to Vocabulary"])
        try history.replaceVocabulary(["SameWave"], in: record)
        try history.attach([.init(fileName: "release-plan.md", content: "XPay SwiftData OAuth"),
                            .init(fileName: "technical-notes.md", content: "SameWave")], to: record)
        let url = FileManager.default.temporaryDirectory.appending(path: "VocabularyStates-\(UUID()).md")
        try "XPay SwiftData OAuth".write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        defer { importer.reset() }
        importer.start(from: [url], using: ControlledVocabularyProvider([.content(#"{"phrases":["XPay","SwiftData","OAuth"]}"#)]))
        try await Phase2Fixture.waitUntil { !importer.isRunning }
        try await render(view, size: size, name: "phase2-vocabulary-ready",
            expectedLabels: ["Suggested Terms", "XPay", "SwiftData", "OAuth", "Meeting Vocabulary", "Add to Vocabulary"],
            absentLabels: ["Review", "No new terms found."])
        importer.saveSelected()
        importer.start(from: [url], using: ControlledVocabularyProvider([.content(#"{"phrases":["SameWave"]}"#)]))
        try await Phase2Fixture.waitUntil { !importer.isRunning }
        try await render(view, size: size, name: "phase2-vocabulary-no-new-terms",
            expectedLabels: ["No new terms found.", "Meeting Vocabulary", "Configure", "Done"],
            absentLabels: ["Suggested Terms", "Review", "Request Details"])
        importer.reset()
        importer.candidates = (1...40).map { .init(originalPhrase: "Term \($0)", text: "Term \($0)") }
        try await render(view, size: size, name: "phase2-vocabulary-long-list",
            expectedLabels: ["Suggested Terms", "Discard Suggestions", "40 selected", "Done", "Add to Vocabulary"],
            absentLabels: ["Review"])
    }

    func testPersonalVocabularyUsesSameEditorAndLocalFileControls() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let personal = SpeechVocabularySettings(defaults: defaults)
        personal.save(["SameWave"])
        let editor = VocabularyEditorStore(aiSettings: settings, settings: personal)
        let url = FileManager.default.temporaryDirectory.appending(path: "Personal-\(UUID()).md")
        try "PRIVATE CONTENT NOT SHOWN".write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        editor.chooseFiles(.success([url]))
        try await Phase2Fixture.waitUntil { !editor.isLoadingFiles }
        editor.importer.candidates = [.init(originalPhrase: "XPay", text: "XPay")]
        let view = VocabularyEditorView(editor: editor)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
        try await render(view, size: NSSize(width: 600, height: 540), name: "unified-vocabulary-personal",
            expectedLabels: ["Personal Vocabulary", "Across meetings", "Choose Markdown", "temporary file selected",
                             "Suggested Terms", "Add to Vocabulary", "Discard Suggestions", "Done"],
            absentLabels: ["PRIVATE CONTENT NOT SHOWN", "Review", "Request Details", "Manage Context"])
        editor.importer.reset()
        editor.isAddingTerms = true
        editor.manualText = "Paste one phrase per line\nXPay"
        try await render(view, size: NSSize(width: 600, height: 540), name: "unified-vocabulary-manual",
            expectedLabels: ["Personal Vocabulary", "Saved Vocabulary", "One phrase per line", "Add Terms", "Hide"],
            absentLabels: ["Review", "PRIVATE CONTENT NOT SHOWN"])
    }

    func testVocabularyLongReviewPreservesPositionAcrossArrivalAndReopen() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let personal = SpeechVocabularySettings(defaults: defaults)
        personal.save([])
        let editor = VocabularyEditorStore(aiSettings: settings, settings: personal)
        editor.importer.candidates = (1...100).map { .init(originalPhrase: "Term \($0)", text: "Term \($0)") }
        let navigation = SettingsNavigation(aiSettings: settings, vocabularyEditor: editor)
        navigation.selectedTab = .vocabulary
        func makeController() -> NSHostingController<some View> {
            NSHostingController(rootView: SettingsView().environment(navigation)
                .background(Color(nsColor: .windowBackgroundColor)))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var controller = makeController()
        window.contentViewController = controller
        var host = controller.view
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(60))
        host.layoutSubtreeIfNeeded()
        var scroll = try XCTUnwrap(findVocabularyScroll(in: host))
        // Position the native clip view directly: a synthetic wheel event inherits
        // the desktop pointer location and can be rejected outside this test window.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 650))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(editor.scrollOffset, 650, accuracy: 1)
        navigation.openAISettings()
        try await Task.sleep(for: .milliseconds(60))
        editor.importer.candidates.append(.init(originalPhrase: "New Arrival", text: "New Arrival"))
        navigation.selectedTab = .vocabulary
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 650, accuracy: 1)
        window.contentViewController = nil
        window.close()
        try await Task.sleep(for: .milliseconds(30))
        controller = makeController()
        window.contentViewController = controller
        host = controller.view
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        scroll = try XCTUnwrap(findVocabularyScroll(in: host))
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 650, accuracy: 1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1_300))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(editor.scrollOffset, 1_300, accuracy: 1)
        let document = try XCTUnwrap(scroll.documentView)
        let bottom = document.frame.height - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(60))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/embedded-vocabulary-long-bottom.png"))
        let labels = try visibleText(host)
        XCTAssertTrue(labels.contains("Discard Suggestions"), labels)
        XCTAssertTrue(labels.contains("Add to Vocabulary"), labels)
        XCTAssertTrue(labels.contains("Deselect All"), labels)
        XCTAssertTrue(labels.contains("Done"), labels)
    }

    private func findVocabularyScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        // Settings keeps both tabs mounted; this fixture's 100-term list is taller than the AI form.
        return view.subviews.compactMap { self.findVocabularyScroll(in: $0) }
            .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }

    func testVocabularyIsEmbeddedDirectlyInSettings() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let personal = SpeechVocabularySettings(defaults: defaults)
        personal.save(["XPay"])
        let editor = VocabularyEditorStore(aiSettings: settings, settings: personal)
        let navigation = SettingsNavigation(aiSettings: settings, vocabularyEditor: editor)
        navigation.selectedTab = .vocabulary
        try await render(SettingsView().environment(navigation), size: NSSize(width: 600, height: 540),
            name: "embedded-vocabulary-settings",
            expectedLabels: ["Settings", "Services", "Vocabulary", "Personal Vocabulary", "Across meetings", "Extract from Markdown",
                             "Choose Markdown", "Saved Vocabulary", "Add Terms", "Done"],
            absentLabels: ["Manage Vocabulary", "separate window", "Review", "Request Details"])
        editor.beginEditing("XPay")
        editor.editedText = ""
        try await render(SettingsView().environment(navigation), size: NSSize(width: 600, height: 540),
            name: "vocabulary-invalid-term",
            expectedLabels: ["Invalid term", "Save", "Cancel", "Done"])
        editor.cancelEditing()
        editor.importer.candidates = [.init(originalPhrase: "SwiftData", text: "SwiftData")]
        navigation.aiDraft.customModel = "Pending model"
        try await render(SettingsView().environment(navigation), size: NSSize(width: 600, height: 540),
            name: "embedded-vocabulary-suggestions",
            expectedLabels: ["Suggested Terms", "Add to Vocabulary", "Discard Suggestions", "Services has unsaved changes", "Done"])
    }

    func testMultipartOverviewAndFullSummaryRenderWithoutDisclosure() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let definition = try XCTUnwrap(record.definitions.first)
        let input = Phase2Fixture.input(record: record, configuration: definition.configuration, kind: .automatic)
        let value = InsightSnapshotValue(id: UUID(), input: input, completedAt: .now,
            result: InsightResult(conclusion: "Friday’s launch remains conditional on security review.",
                                  points: [], summary: Phase2Fixture.summary))
        try history.appendInsight(value)
        try await render(InsightResultCard(meetingID: record.id, configuration: definition.configuration, snapshots: record.insightSnapshots,
            tone: 0, state: .saved, automatic: true, generate: {}),
            size: NSSize(width: 256, height: 980), name: "phase2-live-overview-parts",
            expectedLabels: ["Topics", "Suggestions"], absentLabels: ["Details"])
        try history.appendInsight(Phase2Fixture.snapshot(record: record))
        let summarySnapshots = record.insightSnapshots.filter { $0.definitionID == InsightConfiguration.summary.id }
        try await render(InsightResultCard(meetingID: record.id, configuration: .summary, snapshots: summarySnapshots,
            state: .saved, generate: {}),
            size: NSSize(width: 216, height: 740), name: "phase2-full-summary-parts",
            expectedLabels: ["Topics", "Suggestions", "Action Items", "Decisions", "Open Questions"],
            absentLabels: ["Full Meeting Summary", "Launch depends on security review.", "Details"])
    }

    func testMeetingSectionsExistBeforeGenerationAndThroughFailure() async throws {
        let meetingID = UUID()
        let states: [(String, InsightEngine.State?)] = [
            ("empty", nil), ("generating", .generating),
            ("failed", .failed("The AI service is unavailable. Try again.")), ("cancelled", .cancelled)
        ]
        for (name, state) in states {
            try await render(InsightResultCard(meetingID: meetingID, configuration: .summary, snapshots: [],
                state: state, canGenerate: true, generate: {}, stop: {}),
                size: NSSize(width: 216, height: 660), name: "phase2-sections-\(name)",
                expectedLabels: ["Topics", "Suggestions", "Action Items", "Decisions", "Open Questions", "No content yet."],
                absentLabels: ["Full Meeting Summary", "No decisions recorded.", "Details"])
        }
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let unsaved = Phase2Fixture.snapshot(record: record)
        try await render(InsightResultCard(meetingID: record.id, configuration: .summary, snapshots: [],
            state: .unsaved("The result could not be saved."), unsaved: [unsaved], generate: {}, retrySave: { _ in }),
            size: NSSize(width: 216, height: 820), name: "phase2-sections-unsaved",
            expectedLabels: ["Topics", "Suggestions", "Action Items", "Decisions", "Open Questions", "Retry Save"],
            absentLabels: ["Full Meeting Summary", "No content yet.", "Details"])
    }

    func testCustomSavedAndUnsavedPointsRemainVisibleWithoutDetails() async throws {
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let configuration = InsightConfiguration(id: UUID(), title: "Launch Risks", prompt: "Identify risks", scope: .cumulative)
        let value = InsightSnapshotValue(id: UUID(), input: Phase2Fixture.input(record: record, configuration: configuration, kind: .manual),
            completedAt: .now, result: InsightResult(conclusion: "Security review is pending.", points: ["Confirm the review owner."]))
        try history.appendInsight(value)
        try await render(InsightResultCard(meetingID: record.id, configuration: configuration, snapshots: record.insightSnapshots),
            size: NSSize(width: 240, height: 340), name: "phase2-custom-content",
            expectedLabels: ["Security review is pending.", "1 key point", "Confirm the review owner."], absentLabels: ["Details"])
        try await render(InsightResultCard(meetingID: record.id, configuration: configuration, snapshots: [],
            state: .unsaved("Save failed."), unsaved: [value], retrySave: { _ in }),
            size: NSSize(width: 240, height: 340), name: "phase2-custom-unsaved-content",
            expectedLabels: ["Confirm the review owner.", "Retry Save"], absentLabels: ["Details", "No saved insight yet."])
    }

    func testCustomInsightBatchHeaderParallelAndQueuedCardsRender() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.beginCapture(record, languagePair: .englishToEnglish)
        let definition = InsightDefinition(title: "Launch Risks", prompt: "Identify risks")
        definition.createdAt = record.orderedDefinitions[0].createdAt.addingTimeInterval(1)
        definition.record = record
        history.context.insert(definition)
        try history.save()
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let settings = AISettings(defaults: defaults)
        let engine = InsightEngine(settings: settings, history: history, providerFactory: { provider })
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        coordinator.insights = engine
        coordinator.selectedHistoryRecord = record
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 20)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        XCTAssertEqual(engine.states.values.filter { $0 == .generating }.count, 2)
        try await render(InsightInspector(coordinator: coordinator)
            .environment(settings).environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults)).defaultAppStorage(defaults),
            size: NSSize(width: 240, height: 620), name: "phase2-custom-batch",
            expectedLabels: ["Custom Insights", "Stop", "Updating", "Your insight will appear here."],
            absentLabels: ["Generate when you’re ready."])
        engine.cancelBatch(record.id)
        try await render(InsightResultCard(meetingID: record.id, configuration: definition.configuration, snapshots: [],
            state: .queued, generate: {}, stop: {}), size: NSSize(width: 240, height: 340), name: "phase2-custom-queued",
            expectedLabels: ["Queued", "Stop", "Your insight will appear here."])
    }

    func testKeyPointExpansionRestoresAcrossViewsAndVersionsWithoutAffectingOtherInsights() async throws {
        let suite = "SameWaveTests.PointExpansion.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let configuration = try XCTUnwrap(record.definitions.first).configuration
        let key = InsightKey(meetingID: record.id, definitionID: configuration.id)
        let point = "Confirm the review owner."
        let value = InsightSnapshotValue(id: UUID(),
            input: Phase2Fixture.input(record: record, configuration: configuration, kind: .manual),
            completedAt: .now, result: InsightResult(conclusion: "Review is pending.", points: [point]))
        try history.appendInsight(value)
        defaults.set(false, forKey: key.pointsExpansionStorageKey)
        let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try await render(InsightResultCard(meetingID: record.id, configuration: configuration, snapshots: record.insightSnapshots)
            .defaultAppStorage(restoredDefaults), size: NSSize(width: 240, height: 340), name: "phase2-points-collapsed",
            expectedLabels: ["1 key point"], absentLabels: [point])

        let newValue = InsightSnapshotValue(id: UUID(),
            input: Phase2Fixture.input(record: record, configuration: configuration, kind: .manual,
                                       now: value.input.requestedAt.addingTimeInterval(1)),
            completedAt: .now, result: value.result)
        try history.appendInsight(newValue)
        try await render(InsightResultCard(meetingID: record.id, configuration: configuration, snapshots: record.insightSnapshots)
            .defaultAppStorage(restoredDefaults), size: NSSize(width: 240, height: 340), name: "phase2-points-new-version",
            expectedLabels: ["1 key point"], absentLabels: [point])
        try await render(InsightResultCard(meetingID: UUID(), configuration: configuration, snapshots: record.insightSnapshots)
            .defaultAppStorage(restoredDefaults), size: NSSize(width: 240, height: 340), name: "phase2-points-other-meeting",
            expectedLabels: [point])
        var otherConfiguration = configuration
        otherConfiguration.id = UUID()
        try await render(InsightResultCard(meetingID: record.id, configuration: otherConfiguration, snapshots: record.insightSnapshots)
            .defaultAppStorage(restoredDefaults), size: NSSize(width: 240, height: 340), name: "phase2-points-other-insight",
            expectedLabels: [point])
        restoredDefaults.set(true, forKey: key.pointsExpansionStorageKey)
        try await render(InsightResultCard(meetingID: record.id, configuration: configuration, snapshots: record.insightSnapshots)
            .defaultAppStorage(defaults), size: NSSize(width: 240, height: 340), name: "phase2-points-expanded",
            expectedLabels: [point])
    }

    private func render<V: View>(_ view: V, size: NSSize, name: String,
                                 expectedLabels: [String] = [], absentLabels: [String] = [],
                                 alignedLabels: (String, String)? = nil) async throws {
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.bounds.size, size)
        try capture(host, name: name)
        try savePNG(host, name: name)
        if !expectedLabels.isEmpty || !absentLabels.isEmpty {
            // OCR normalizes typographic spaces and reports wrapped labels as separate lines.
            func normalized(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            let labels = normalized(try visibleText(host))
            for label in expectedLabels { XCTAssertTrue(labels.contains(normalized(label)), "Missing \(label) in \(labels)") }
            for label in absentLabels { XCTAssertFalse(labels.contains(normalized(label)), "Unexpected \(label) in \(labels)") }
        }
        if let (title, action) = alignedLabels {
            let observations = try visibleTextObservations(host)
            let heading = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string.contains(title) == true })
            let button = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string.contains(action) == true })
            XCTAssertEqual(heading.boundingBox.minY, button.boundingBox.minY, accuracy: 0.015,
                           "The preparation title and Done must share a header row")
            XCTAssertGreaterThan(heading.boundingBox.minY, 0.9, "No empty row above the heading")
        }
    }

    private func visibleText(_ view: NSView) throws -> String {
        try visibleTextObservations(view).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func visibleTextObservations(_ view: NSView) throws -> [VNRecognizedTextObservation] {
        // Verify the pixels: hidden test windows do not publish a SwiftUI accessibility tree.
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Bundle.main.preferredLocalizations.first == "zh-Hans" ? ["zh-Hans", "en-US"] : ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
        return request.results ?? []
    }

    private func capture<V: View>(_ host: NSHostingView<V>, name: String) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func savePNG<V: View>(_ host: NSHostingView<V>, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        try data.write(to: root.appendingPathComponent(".build/\(name).png"))
    }
}
