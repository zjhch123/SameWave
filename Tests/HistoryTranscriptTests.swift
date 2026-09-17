import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class HistoryTranscriptTests: XCTestCase {
    func testMountedHistoryObservesRefinementAndNewLines() async throws {
        let history = try MeetingHistoryStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let line = makeLine(source: "Original source.", target: "原始译文。")
        let record = makeRecord(lines: [line])
        history.context.insert(record)
        try history.context.save()
        let host = NSHostingView(rootView: HistoryDetailView(record: record, showRefined: true))
        let window = makeWindow(host)
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findTranscript(in: host))
        XCTAssertTrue(scroll.transcriptTextView.string.contains("Original source."))
        line.refinedSource = "Corrected source."
        line.refinedTarget = "修订后的译文。"
        try history.context.save()
        try await settle(host)
        XCTAssertTrue(scroll.transcriptTextView.string.contains("Corrected source."))
        XCTAssertTrue(scroll.transcriptTextView.string.contains("修订后的译文。"))
        XCTAssertFalse(scroll.transcriptTextView.string.contains("Original source."))

        record.lines.append(makeLine(source: "Another saved sentence.", target: "另一句已保存的文字。", id: 1))
        try history.context.save()
        try await settle(host)
        XCTAssertTrue(scroll.transcriptTextView.string.contains("Another saved sentence."))
        XCTAssertTrue(scroll.transcriptTextView.string.contains("Corrected source."))
    }

    func testNativeSelectionCopyAndUnchangedUpdatePreserveReadingState() async throws {
        let lines = (0..<40).map { makeLine(source: "Saved sentence \($0).", target: "第 \($0) 句译文。", id: $0) }
        let record = makeRecord(lines: lines)
        let host = NSHostingView(rootView: HistoryDetailView(record: record))
        let window = makeWindow(host)
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findTranscript(in: host))
        let textView = scroll.transcriptTextView
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertEqual(textView.accessibilityRole(), .textArea)
        let selection = (textView.string as NSString).range(of: "Saved sentence 10.")
        XCTAssertNotEqual(selection.location, NSNotFound)
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        try await settle(host)
        let offset = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(offset, 0)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string), "Saved sentence 10.")

        host.rootView = HistoryDetailView(record: record)
        try await settle(host)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 1)
    }

    func testSwitchingToShortAndEmptyHistoryReplacesTextAndClampsScroll() async throws {
        let lines = (0..<40).map { makeLine(source: "Earlier meeting sentence \($0).", target: "原有译文。", id: $0) }
        let host = NSHostingView(rootView: HistoryDetailView(record: makeRecord(lines: lines)))
        let window = makeWindow(host)
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findTranscript(in: host))
        let textView = scroll.transcriptTextView
        let bottom = textView.frame.height - scroll.contentSize.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(host)

        host.rootView = HistoryDetailView(record: makeRecord(lines: [
            makeLine(source: "New meeting source.", target: "新的译文。")
        ]))
        try await settle(host)
        XCTAssertTrue(textView.string.contains("New meeting source."))
        XCTAssertFalse(textView.string.contains("Earlier meeting"))
        XCTAssertEqual(textView.frame.height, scroll.contentSize.height, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1)

        host.rootView = HistoryDetailView(record: makeRecord(lines: []))
        try await settle(host)
        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.frame.height, scroll.contentSize.height, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1)
    }

    func testSourceEchoAndMissingTranslationsRemainReadable() {
        let untranslated = "Waiting for the saved translation."
        let record = makeRecord(lines: [
            makeLine(source: "Original text.", target: "译文。"),
            makeLine(source: untranslated, target: "", id: 1)
        ])
        let transcript = HistoryTranscript(record: record)
        let bilingual = transcript.attributedText(hideSourceEcho: false).string
        XCTAssertTrue(bilingual.contains("译文。"))
        XCTAssertTrue(bilingual.contains("Original text."))
        XCTAssertEqual(bilingual.components(separatedBy: untranslated).count, 2)
        let sourceOnly = transcript.attributedText(hideSourceEcho: true).string
        XCTAssertFalse(sourceOnly.contains("译文。"))
        XCTAssertEqual(sourceOnly.components(separatedBy: "Original text.").count, 2)
        XCTAssertEqual(sourceOnly.components(separatedBy: untranslated).count, 2)
    }

    private func makeLine(source: String, target: String, id: Int = 0) -> TranscriptLine {
        TranscriptLine(speaker: .remote, sourceText: source, targetText: target,
                       spokenAt: Date(timeIntervalSince1970: Double(id * 40)), orderIndex: id, sectionId: id)
    }

    private func makeRecord(lines: [TranscriptLine]) -> MeetingRecord {
        MeetingRecord(startedAt: .now, endedAt: .now, languagePair: .englishToSimplifiedChinese,
                      lineCount: lines.count, status: .ended, lines: lines)
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>) -> NSWindow {
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
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

    private func findTranscript(in view: NSView) -> HistoryTextScrollView? {
        if let scroll = view as? HistoryTextScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findTranscript(in: $0) }.first
    }
}
