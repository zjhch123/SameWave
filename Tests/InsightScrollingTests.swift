import AppKit
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class InsightScrollingTests: XCTestCase {
    func testMixedHeightInsightsKeepDocumentHeightAndScrollPosition() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let overview = try XCTUnwrap(record.orderedDefinitions.first)
        try history.appendInsight(Phase2Fixture.snapshot(record: record, configuration: overview.configuration))
        for index in 0..<8 {
            let definition = InsightDefinition(title: "Review \(index)", prompt: "Review the release plan")
            definition.createdAt = record.createdAt.addingTimeInterval(Double(index + 1))
            definition.record = record
            history.context.insert(definition)
            let point = "Confirm the security review owner and the rollout date before committing to the release."
            let result = InsightResult(conclusion: "Release review \(index).",
                points: Array(repeating: point, count: index.isMultiple(of: 2) ? 12 : 1))
            try history.appendInsight(InsightSnapshotValue(id: UUID(),
                input: Phase2Fixture.input(record: record, configuration: definition.configuration, kind: .manual),
                completedAt: .now, result: result))
        }
        try history.finish(record, sections: [], endedAt: .now)
        try history.appendInsight(Phase2Fixture.snapshot(record: record))
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults),
                                             defaults: defaults)
        coordinator.history = history
        coordinator.selectedHistoryRecord = record
        let host = NSHostingView(rootView: InsightInspector(coordinator: coordinator)
            .environment(AISettings(defaults: defaults)).environment(Phase2Fixture.settingsNavigation(AISettings(defaults: defaults), defaults: defaults)))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        for width in [280.0, 240.0] {
            window.setContentSize(NSSize(width: width, height: 480))
            try await settle(host)
            let scroll = try XCTUnwrap(findScrollView(in: host))
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(host)
            let document = try XCTUnwrap(scroll.documentView)
            let height = document.frame.height
            let maximumOffset = height - scroll.contentView.bounds.height
            XCTAssertGreaterThan(maximumOffset, 1_000, "The fixture must exercise offscreen cards")
            let offsets = stride(from: 0.0, through: maximumOffset, by: 160.0).map { $0 } + [maximumOffset]
            for offset in offsets + offsets.reversed() {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(host)
                XCTAssertEqual(document.frame.height, height, accuracy: 1,
                               "Scrolling must not re-estimate content height at width \(width), offset \(offset)")
                XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 1,
                               "Unchanged cards must not shift the requested scroll position")
            }
        }
    }

    private func settle(_ view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        view.layoutSubtreeIfNeeded()
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}
