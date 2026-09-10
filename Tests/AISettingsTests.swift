import AppKit
import SwiftUI
import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class AISettingsTests: XCTestCase {
    func testEveryProviderRequiresANonblankKey() {
        for provider in LLMProviderConfig.builtIn {
            for key in ["", " \n\t"] {
                XCTAssertFalse(AISettings.isConfigured(
                    provider: provider, apiKey: key,
                    customAPIAddress: "https://example.com/v1", customModel: "model"
                ), provider.id)
            }
        }
    }

    func testBuiltInServicesNeedNoCustomConfiguration() {
        for provider in LLMProviderConfig.builtIn where !provider.isCustom {
            XCTAssertTrue(AISettings.isConfigured(
                provider: provider, apiKey: " test-key ",
                customAPIAddress: "", customModel: ""
            ), provider.id)
        }
    }

    func testCustomServiceRequiresBothUsableAddressAndModel() {
        for (address, model) in [("", "model"), ("ftp://example.com", "model"),
                                 ("https://example.com", " \n")] {
            XCTAssertFalse(AISettings.isConfigured(
                provider: .custom, apiKey: "test-key",
                customAPIAddress: address, customModel: model
            ))
        }
        for address in ["api.example.com", "http://localhost:8080/v1",
                        "https://example.com/v1/chat/completions"] {
            XCTAssertTrue(AISettings.isConfigured(
                provider: .custom, apiKey: "test-key",
                customAPIAddress: address, customModel: "model"
            ))
        }
    }

    func testUnconfiguredServiceBlocksEveryAIConsumer() async throws {
        let defaults = isolatedDefaults()
        let settings = AISettings(defaults: defaults)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        let history = try MeetingHistoryStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let insights = InsightEngine(settings: settings, history: history)
        let refiner = TranscriptRefiner(settings: settings, vocabularySettings: vocabulary)
        let editor = VocabularyEditorStore(aiSettings: settings, settings: vocabulary)
        let importer = editor.importer

        XCTAssertFalse(settings.isConfigured)
        XCTAssertNil(settings.makeProvider())
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let definition = try XCTUnwrap(record.definitions.first)
        insights.generate(record: record, configuration: definition.configuration, kind: .manual,
                          sources: [], vocabulary: [], elapsedSeconds: 0)
        XCTAssertEqual(insights.states[InsightKey(meetingID: record.id, definitionID: definition.id)],
                       .failed(LLMError.notConfigured.localizedDescription))
        do {
            _ = try await refiner.refine(
                lines: [],
                languagePair: .init(source: .english, target: .simplifiedChinese),
                priorGlossaryJSON: nil
            )
            XCTFail("Refinement must require the shared AI configuration")
        } catch {
            XCTAssertEqual(error as? LLMError, .notConfigured)
        }
        do {
            _ = try await MeetingTitleGenerator.generateIfNeeded(for: record, provider: settings.makeProvider())
            XCTFail("Titles must require the shared AI configuration")
        } catch {
            XCTAssertEqual(error as? LLMError, .notConfigured)
        }
        XCTAssertFalse(importer.isAvailable)
        importer.start(documents: [.init(fileName: "test.md", content: "SameWave")])
        XCTAssertEqual(importer.state, .failed(LLMError.notConfigured.localizedDescription))
        XCTAssertTrue(importer.requests.isEmpty)

        // Editing a local vocabulary remains available without AI.
        editor.manualText = "SameWave"
        editor.addTerms()
        XCTAssertTrue(vocabulary.phrases.contains("SameWave"))
    }

    func testAISettingsRouteSelectsAITabAndPreservesVocabularyDraft() async throws {
        let defaults = isolatedDefaults()
        let settings = AISettings(defaults: defaults)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        vocabulary.save(["Saved"])
        let editor = VocabularyEditorStore(aiSettings: settings, settings: vocabulary)
        editor.manualText = "Saved\nUnsaved"
        let navigation = SettingsNavigation(aiSettings: settings, vocabularyEditor: editor)
        navigation.selectedTab = .vocabulary
        let host = NSHostingView(rootView: SettingsView().environment(navigation)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = makeWindow(host: host)
        defer { window.close() }
        await Task.yield()
        try capture(host, name: "Vocabulary settings with AI service link")

        let hostID = UUID()
        window.orderFront(nil)
        navigation.register(hostID, window: window)
        navigation.openAISettings()
        XCTAssertEqual(navigation.selectedTab, .ai)
        await Task.yield()
        try capture(host, name: "App-wide AI service settings")

        XCTAssertEqual(navigation.presentedHost, hostID)
        XCTAssertEqual(editor.manualText, "Saved\nUnsaved")
        XCTAssertEqual(vocabulary.phrases, ["Saved"])
    }

    func testCustomAISettingsRenderWithinSettingsWindow() async throws {
        let settings = AISettings(defaults: isolatedDefaults())
        settings.selectedProviderID = LLMProviderConfig.custom.id
        settings.customAPIAddress = "http://localhost:8080/v1"
        settings.customModel = "my-model"
        let host = NSHostingView(rootView: AISettingsView(controller: AISettingsController(settings: settings))
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = makeWindow(host: host)
        defer { window.close() }
        await Task.yield()
        try capture(host, name: "Custom AI service settings")
        XCTAssertFalse(settings.isConfigured)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "AISettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeWindow<V: View>(host: NSHostingView<V>) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
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
}
