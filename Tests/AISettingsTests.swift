import AppKit
import SwiftUI
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
        let insights = InsightEngine(settings: settings, vocabularySettings: vocabulary)
        let refiner = TranscriptRefiner(settings: settings, vocabularySettings: vocabulary)
        let title = MeetingTitleGenerator(settings: settings)
        let draft = SpeechVocabularyDraft(settings: vocabulary)
        let importer = VocabularyImportController(aiSettings: settings, vocabularyDraft: draft)

        XCTAssertFalse(settings.isConfigured)
        XCTAssertNil(settings.makeProvider())
        do {
            _ = try await insights.generateOnce(transcript: "对方：项目进度")
            XCTFail("Insights must require the shared AI configuration")
        } catch {
            XCTAssertEqual(error as? LLMError, .notConfigured)
        }
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
            _ = try await title.generate(lines: [])
            XCTFail("Titles must require the shared AI configuration")
        } catch {
            XCTAssertEqual(error as? LLMError, .notConfigured)
        }
        XCTAssertFalse(importer.canStartOrResume)
        XCTAssertTrue(importer.handleFileSelection(.success([URL(filePath: "/unused.md")])))
        XCTAssertEqual(importer.state, .failed(LLMError.notConfigured.localizedDescription))
        XCTAssertTrue(importer.requests.isEmpty)

        // Editing a local vocabulary remains available without AI.
        draft.text = "SameWave"
        draft.save()
        XCTAssertEqual(vocabulary.phrases, ["SameWave"])
    }

    func testAISettingsRouteSelectsAITabAndPreservesVocabularyDraft() async throws {
        let defaults = isolatedDefaults()
        let settings = AISettings(defaults: defaults)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        vocabulary.save(["Saved"])
        let draft = SpeechVocabularyDraft(settings: vocabulary)
        draft.text = "Saved\nUnsaved"
        let navigation = SettingsNavigation()
        navigation.selectedTab = .vocabulary
        let controller = VocabularyImportController(aiSettings: settings, vocabularyDraft: draft)
        let host = NSHostingView(rootView: SettingsView(
            aiSettings: settings, speechVocabularyDraft: draft,
            vocabularyImportController: controller
        ).environment(navigation)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = makeWindow(host: host)
        defer { window.close() }
        await Task.yield()
        try capture(host, name: "Vocabulary settings with AI service link")

        var didOpen = false
        navigation.openAISettings {
            XCTAssertEqual(navigation.selectedTab, .ai)
            didOpen = true
        }
        await Task.yield()
        try capture(host, name: "App-wide AI service settings")

        XCTAssertTrue(didOpen)
        XCTAssertEqual(draft.text, "Saved\nUnsaved")
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(vocabulary.phrases, ["Saved"])
    }

    func testCustomAISettingsRenderWithinSettingsWindow() async throws {
        let settings = AISettings(defaults: isolatedDefaults())
        settings.selectedProviderID = LLMProviderConfig.custom.id
        settings.customAPIAddress = "http://localhost:8080/v1"
        settings.customModel = "my-model"
        let host = NSHostingView(rootView: AISettingsView(settings: settings)
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
