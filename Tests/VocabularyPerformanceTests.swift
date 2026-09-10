import AppKit
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class VocabularyPerformanceTests: XCTestCase {
    func testTabSwitchDoesNotRebuildLargeSavedVocabulary() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        vocabulary.save((1...300).map { "Product Term \($0)" })
        var phraseReads = 0
        let editor = VocabularyEditorStore(scope: .personal, aiSettings: settings,
            readPhrases: { phraseReads += 1; return vocabulary.phrases }, replacePhrases: { vocabulary.save($0) })
        let navigation = SettingsNavigation(aiSettings: settings, defaultInsights: DefaultInsightSettings(defaults: defaults), vocabularyEditor: editor)
        let controller = NSHostingController(rootView: SettingsView().environment(navigation))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderFront(nil)
        let host = controller.view
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        var times: [Double] = []
        phraseReads = 0
        for index in 0..<8 {
            let start = ContinuousClock.now
            navigation.selectedTab = index.isMultiple(of: 2) ? .vocabulary : .ai
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let duration = start.duration(to: .now).components
            times.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            try await Task.sleep(for: .milliseconds(20))
        }
        let report = "300 saved terms; 8 tab switches; phrase reads: \(phraseReads); milliseconds: \(times)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(phraseReads, 0, "Tab navigation must not re-read and rebuild the saved term list")
        XCTAssertEqual(editor.phrases.count, 300)
    }

    func testLongSavedVocabularyKeepsScrollGeometryAndEdits() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults)
        let vocabulary = SpeechVocabularySettings(defaults: defaults)
        vocabulary.save((1...300).map { index in
            index.isMultiple(of: 3) ? "Product \(index) " + String(repeating: "extended name ", count: 6) : "Product \(index)"
        })
        let editor = VocabularyEditorStore(aiSettings: settings, settings: vocabulary)
        let navigation = SettingsNavigation(aiSettings: settings, defaultInsights: DefaultInsightSettings(defaults: defaults), vocabularyEditor: editor)
        navigation.selectedTab = .vocabulary
        let controller = NSHostingController(rootView: SettingsView().environment(navigation))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderFront(nil)
        try await settle(controller.view)
        let scroll = try XCTUnwrap(longestScroll(in: controller.view))
        let document = try XCTUnwrap(scroll.documentView)
        let height = document.frame.height
        let maximumOffset = height - scroll.contentView.bounds.height
        XCTAssertGreaterThan(maximumOffset, 9_000)
        for offset in [650.0, 2_000, 6_000, maximumOffset, 6_000, 2_000, 650] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(controller.view)
            XCTAssertEqual(document.frame.height, height, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 1)
        }
        let phrase = vocabulary.phrases[20]
        editor.beginEditing(phrase)
        editor.editedText = "Pending replacement"
        try await settle(controller.view)
        let offset = scroll.contentView.bounds.origin.y
        navigation.openAISettings()
        try await settle(controller.view)
        navigation.selectedTab = .vocabulary
        try await settle(controller.view)
        XCTAssertEqual(editor.editingPhrase, phrase)
        XCTAssertEqual(editor.editedText, "Pending replacement")
        XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 1)
        editor.editedText = ""
        try await settle(controller.view)
        let invalidHeight = document.frame.height
        XCTAssertEqual(invalidHeight, height, accuracy: 1)
        for offset in [2_000.0, 6_000, 650] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(controller.view)
            XCTAssertEqual(document.frame.height, invalidHeight, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 1)
        }
        editor.cancelEditing()
        try await settle(controller.view)
        XCTAssertEqual(document.frame.height, height, accuracy: 1)
    }

    private func settle(_ view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
        view.layoutSubtreeIfNeeded()
    }

    private func longestScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.compactMap { longestScroll(in: $0) }
            .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }
}
