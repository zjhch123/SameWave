import AppKit
import SwiftUI
import Vision
import XCTest
@testable import SameWave

@MainActor
final class SimpleCaptionTests: XCTestCase {
    func testCompleteBilingualParagraphMatchesFullWindow() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        let source = ["The first sentence.", "The second sentence.", "The third sentence.", "The fourth sentence."]
        let target = ["第一句。", "第二句。", "第三句。", "第四句。"]
        coordinator.store.restore(sections: source.indices.map { index in
            (id: index, speaker: .remote, source: source[index], target: target[index], startedAt: Date(timeIntervalSince1970: 0))
        })
        XCTAssertEqual(coordinator.store.paragraphLayout.paragraphs.map(\.sectionIDs), [[0, 1, 2, 3]])
        let simple = NSHostingView(rootView: SimpleCaptionsView(coordinator: coordinator, onShowFullWindow: {})
            .defaultAppStorage(defaults))
        let full = NSHostingView(rootView: CaptionsView(store: coordinator.store))
        let simpleWindow = makeWindow(simple)
        let fullWindow = makeWindow(full)
        defer { simpleWindow.close(); fullWindow.close() }
        try await settle(simple)
        try await settle(full)
        let simpleText = try visibleText(in: XCTUnwrap(findScroll(in: simple)).contentView)
        let fullText = try visibleText(in: XCTUnwrap(findScroll(in: full)).contentView)
        XCTAssertEqual(simpleText, fullText)
        for sentence in source { XCTAssertTrue(simpleText.contains(sentence), simpleText) }
        for sentence in ["第一句", "第二句", "第三句", "第四句"] {
            XCTAssertTrue(simpleText.contains(sentence), simpleText)
        }
        XCTAssertTrue(simpleText.contains(String(localized: "Speaker")))
        XCTAssertFalse(simpleText.contains("Other party"))
    }

    func testCompleteConversationRemainsScrollableWhileNewCaptionsArrive() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.setStatus(record, .paused)
        await coordinator.loadSession(record)
        for index in 0..<36 {
            let source = index == 0 ? "The first historical caption begins here." : "Historical caption number \(index)."
            coordinator.store.updateSource(source, speaker: .remote, isFinal: true)
            coordinator.store.setNativeCaption(id: index)
        }
        let host = NSHostingView(rootView: SimpleCaptionsView(coordinator: coordinator, onShowFullWindow: {})
            .defaultAppStorage(defaults))
        let window = makeWindow(host)
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 100)
        let latestText = try visibleText(in: host)
        XCTAssertTrue(latestText.contains("Historical caption number 35."), latestText)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(host)
        let offset = scroll.contentView.bounds.minY
        let firstText = try visibleText(in: host)
        XCTAssertTrue(firstText.contains("The first historical caption begins here."), firstText)
        coordinator.store.updateSource("The newest sentence is still arriving", speaker: .remote, isFinal: false)
        coordinator.store.setNativeCaption(id: 36)
        try await settle(host)
        XCTAssertEqual(scroll.contentView.bounds.minY, offset, accuracy: 1)
        let bottom = max(0, scroll.documentView!.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(host)
        coordinator.store.updateSource("The newest sentence is still arriving and now finishes.", speaker: .remote, isFinal: true)
        coordinator.store.setNativeCaption(id: 36)
        try await settle(host)
        XCTAssertLessThanOrEqual(scroll.documentView!.frame.height - scroll.contentView.bounds.maxY, 33)
        let finalText = try visibleText(in: host)
        XCTAssertTrue(finalText.contains("now finishes."), finalText)
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>) -> NSWindow {
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<4 {
            await Task.yield()
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }

    private func visibleText(in view: NSView) throws -> String {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
        return try XCTUnwrap(request.results).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
