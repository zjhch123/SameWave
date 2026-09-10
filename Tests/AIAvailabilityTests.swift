import XCTest
@testable import SameWave

@MainActor
final class AIAvailabilityTests: XCTestCase {
    func testSwitchPersistsAndKeepsCurrentCredentials() {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        settings.selectedProviderID = "custom"
        settings.customAPIAddress = "https://example.com/v1"
        settings.customModel = "saved-model"
        let controller = AISettingsController(settings: settings)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.isAvailable)
        XCTAssertNotNil(settings.makeProvider())
        var cancellations = 0
        settings.onDisable = { cancellations += 1 }
        controller.customModel = "pending-model"
        controller.isEnabled = false
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(settings.isAvailable)
        XCTAssertTrue(settings.isConfigured)
        XCTAssertNil(settings.makeProvider())
        XCTAssertEqual(settings.apiKey, "test-key")
        XCTAssertEqual(controller.customModel, "pending-model")
        XCTAssertFalse(controller.isEnabled)
        let reopened = AISettings(defaults: defaults, initialAPIKey: "test-key")
        XCTAssertFalse(reopened.isEnabled)
        XCTAssertEqual(reopened.customAPIAddress, "https://example.com/v1")
        XCTAssertEqual(reopened.customModel, "pending-model")
        controller.isEnabled = true
        XCTAssertTrue(settings.isAvailable)
        XCTAssertNotNil(settings.makeProvider())
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(AISettings(defaults: defaults).isEnabled)
    }

    func testDisabledServiceBlocksAllGenerationAndKeepsLocalVocabulary() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        settings.isEnabled = false
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.setStatus(record, .ended)
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let engine = InsightEngine(settings: settings, history: history, providerFactory: { provider })
        let definition = try XCTUnwrap(record.definitions.first)
        for (configuration, kind) in [(definition.configuration, InsightKind.manual), (.summary, .summary)] {
            engine.generate(record: record, configuration: configuration, kind: kind,
                            sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 1)
            XCTAssertEqual(engine.states[.init(meetingID: record.id, definitionID: configuration.id)],
                           .failed(LLMError.disabled.localizedDescription))
        }
        engine.generateAll(record: record, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 1)
        XCTAssertFalse(engine.canGenerateAll(record))
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        let controller = MeetingRefinementController(meetingID: record.id, settings: settings,
            vocabulary: vocabulary, history: history, providerFactory: { provider })
        controller.start()
        XCTAssertFalse(controller.isRefining)
        XCTAssertFalse(controller.isGeneratingTitle)
        XCTAssertEqual(controller.errorMessage, LLMError.disabled.localizedDescription)
        do {
            _ = try await controller.refiner.refine(lines: [], languagePair: .englishToEnglish, priorGlossaryJSON: nil)
            XCTFail("The injected provider must not bypass the master switch")
        } catch { XCTAssertEqual(error as? LLMError, .disabled) }
        let editor = VocabularyEditorStore(aiSettings: settings, settings: vocabulary)
        editor.importer.start(documents: [.init(fileName: "test.md", content: "SameWave")])
        XCTAssertEqual(editor.importer.state, .failed(LLMError.disabled.localizedDescription))
        editor.manualText = "SameWave"
        editor.addTerms()
        XCTAssertTrue(vocabulary.phrases.contains("SameWave"))
        let count = await provider.count
        XCTAssertEqual(count, 0)
    }

    func testDisableCancelsActiveAndQueuedInsightsAcrossMeetingsAndKeepsResults() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let first = try history.createDraft(languagePair: .englishToEnglish)
        try history.setStatus(first, .ended)
        for index in 1..<8 {
            let definition = InsightDefinition(title: "Focus \(index)", prompt: "Review focus \(index)")
            definition.record = first
            history.context.insert(definition)
        }
        try history.save()
        let second = try history.createDraft(languagePair: .englishToEnglish)
        try history.setStatus(second, .ended)
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        var failSave = true
        let engine = InsightEngine(settings: settings, history: history, providerFactory: { provider }, saveSnapshot: {
            if failSave { throw CocoaError(.fileWriteOutOfSpace) }
            try history.appendInsight($0)
        })
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.insights = engine
        settings.onDisable = { coordinator.cancelAIWork() }
        engine.generateAll(record: first, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 1)
        engine.generateAll(record: second, sources: Phase2Fixture.source(), vocabulary: [], elapsedSeconds: 1)
        try await Phase2Fixture.waitUntil { await provider.count == 6 }
        try await provider.succeed(0)
        try await Phase2Fixture.waitUntil { await provider.count == 7 }
        XCTAssertEqual(engine.unsaved.count, 1)
        settings.isEnabled = false
        XCTAssertFalse(engine.isWorking(on: first.id))
        XCTAssertFalse(engine.isWorking(on: second.id))
        XCTAssertTrue(engine.batchMeetingIDs.isEmpty)
        for index in 1..<7 { try await provider.succeed(index, conclusion: "Late result") }
        try await Task.sleep(for: .milliseconds(30))
        let count = await provider.count
        XCTAssertEqual(count, 7, "Queued requests must not start after disabling")
        XCTAssertTrue(first.insightSnapshots.isEmpty)
        XCTAssertTrue(second.insightSnapshots.isEmpty)
        failSave = false
        engine.retrySave(try XCTUnwrap(engine.unsaved.keys.first))
        XCTAssertEqual(first.insightSnapshots.count, 1, "Local Retry Save still works while AI is off")
        settings.isEnabled = true
        XCTAssertTrue(engine.canGenerateAll(first))
        XCTAssertFalse(engine.isWorking(on: first.id), "Re-enabling does not restart canceled manual work")
    }

    func testAutomaticSchedulingResumesAfterReenablingWithoutRestartingCapture() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.beginCapture(record, languagePair: .englishToEnglish)
        let definition = try XCTUnwrap(record.definitions.first)
        definition.automaticallyUpdates = true
        let provider = ControlledInsightProvider()
        addTeardownBlock { await provider.releaseAll() }
        let engine = InsightEngine(settings: settings, history: history, providerFactory: { provider })
        settings.onDisable = { engine.cancelAll() }
        let start = Date(timeIntervalSince1970: 1_000)
        engine.startRecording(record, sections: [], now: start)
        var section = Section(id: 0, speaker: .remote)
        section.committedSource = [String(repeating: "Meeting content. ", count: 20)]
        settings.isEnabled = false
        engine.automaticTick(record: record, sections: [section], vocabulary: [], elapsedSeconds: 60,
                             now: start.addingTimeInterval(60))
        XCTAssertTrue(engine.states.isEmpty)
        settings.isEnabled = true
        engine.automaticTick(record: record, sections: [section], vocabulary: [], elapsedSeconds: 61,
                             now: start.addingTimeInterval(61))
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        XCTAssertEqual(record.meetingStatus, .recording)
        settings.isEnabled = false
        try await provider.succeed(0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(record.insightSnapshots.isEmpty)
    }

    func testDisableCancelsBackgroundRefinementAndTitleBeforeNextBatch() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        settings.onDisable = { coordinator.cancelAIWork() }
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let sections = (0..<9).map { index in
            var section = Section(id: index, speaker: .remote)
            section.committedSource = ["Original \(index)"]
            return section
        }
        try history.finish(record, sections: sections, endedAt: .now)
        let provider = ControlledRefinementProvider()
        addTeardownBlock { await provider.failAll() }
        let controller = try XCTUnwrap(coordinator.refinement(for: record, settings: settings, providerFactory: { provider }))
        controller.start()
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        coordinator.selectedHistoryRecord = try history.createDraft(languagePair: .englishToEnglish)
        settings.isEnabled = false
        XCTAssertFalse(controller.isRefining)
        XCTAssertFalse(controller.isGeneratingTitle)
        XCTAssertNil(coordinator.backgroundActivity(for: record.id))
        await provider.completeTranscript(containing: "Original 0", indices: 0..<8, prefix: "Late")
        await provider.completeTitle("Late title")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(record.refinedAt)
        XCTAssertNil(record.aiTitle)
        let count = await provider.count
        XCTAssertEqual(count, 2)
    }

    func testDisableStopsMeetingVocabularyAndBlocksRetryUntilEnabled() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let history = try Phase2Fixture.history()
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        settings.onDisable = { coordinator.cancelAIWork() }
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let editor = coordinator.vocabularyEditor(for: record, settings: settings)
        let file = FileManager.default.temporaryDirectory.appending(path: "ai-switch-\(UUID()).md")
        try String(repeating: "SameWave ", count: 4_000).write(to: file, atomically: true, encoding: .utf8)
        addTeardownBlock { try FileManager.default.removeItem(at: file) }
        let provider = ControlledVocabularyProvider([
            .content(#"{"phrases":["First term"]}"#), .held(#"{"phrases":["Late term"]}"#),
            .content(#"{"phrases":["Retried term"]}"#), .content(#"{"phrases":[]}"#)
        ])
        addTeardownBlock { await provider.release() }
        let importer = editor.importer
        importer.start(from: [file], using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        settings.isEnabled = false
        XCTAssertFalse(importer.isRunning)
        XCTAssertFalse(importer.canRetry)
        XCTAssertEqual(importer.candidates.map(\.text), ["First term"])
        importer.retryIncomplete()
        await provider.release()
        try await Phase2Fixture.waitUntil { await provider.active == 0 }
        XCTAssertEqual(importer.candidates.map(\.text), ["First term"])
        importer.saveSelected()
        XCTAssertEqual(record.confirmedVocabulary, ["First term"])
        settings.isEnabled = true
        XCTAssertTrue(importer.canRetry)
        importer.retryIncomplete()
        try await Phase2Fixture.waitUntil { !importer.isRunning }
        XCTAssertTrue(importer.candidates.contains { $0.text == "Retried term" })
    }
}
