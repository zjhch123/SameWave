import AppKit
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class HistoryPerformanceTests: XCTestCase {
    func testOpeningAndSwitchingLongHistory() async throws {
        let source = "We can review the complete discussion after the meeting ends. "
        let target = "会议结束后，我们可以查看完整的讨论内容，核对原文和译文，并继续阅读下一段。"
        let lines = (0..<500).map { index in
            TranscriptLine(speaker: index.isMultiple(of: 4) ? .mine : .remote,
                           sourceText: "Archive section \(index). " + String(repeating: source, count: 1 + index % 5),
                           targetText: String(repeating: target, count: 1 + index % 7),
                           spokenAt: Date(timeIntervalSince1970: Double(index * 40)),
                           orderIndex: index, sectionId: index,
                           refinedSource: "Refined section \(index). " + String(repeating: source, count: 1 + index % 3),
                           refinedTarget: String(repeating: target, count: 1 + index % 9))
        }
        let record = MeetingRecord(startedAt: .now, endedAt: .now, languagePair: .englishToSimplifiedChinese,
                                   lineCount: lines.count, status: .ended, lines: lines)
        let empty = MeetingRecord(startedAt: .now, endedAt: .now, languagePair: .englishToSimplifiedChinese,
                                  lineCount: 0, status: .ended)
        let host = NSHostingView(rootView: HistoryDetailView(record: empty).id(empty.id))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        var milliseconds: [Double] = []
        for refined in [false, true, false] {
            let start = ContinuousClock.now
            host.rootView = HistoryDetailView(record: record, showRefined: refined).id(record.id)
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let elapsed = start.duration(to: .now).components
            milliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            let scroll = try XCTUnwrap(findTranscript(in: host))
            let textView = scroll.transcriptTextView
            let layout = try XCTUnwrap(textView.layoutManager)
            XCTAssertEqual(layout.firstUnlaidCharacterIndex(), textView.string.utf16.count,
                           "The timing must include complete document layout.")
            XCTAssertGreaterThan(textView.frame.height, 50_000)
            for index in 0..<500 {
                XCTAssertTrue(textView.string.contains("\(refined ? "Refined" : "Archive") section \(index)."))
            }
            let lastGlyph = layout.boundingRect(forGlyphRange: NSRange(location: layout.numberOfGlyphs - 1, length: 1),
                                                in: try XCTUnwrap(textView.textContainer))
            XCTAssertLessThanOrEqual(lastGlyph.maxY + textView.textContainerOrigin.y, textView.frame.height - 39)
            try await Task.sleep(for: .milliseconds(20))
        }
        let report = "500 Sections; native open / Refined / Original milliseconds: \(milliseconds)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThan(try XCTUnwrap(milliseconds.max()), 500,
                          "Opening or changing a long transcript must not block the interface for half a second.")
    }

    private func findTranscript(in view: NSView) -> HistoryTextScrollView? {
        if let scroll = view as? HistoryTextScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findTranscript(in: $0) }.first
    }
}
