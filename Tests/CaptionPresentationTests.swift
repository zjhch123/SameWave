import AppKit
import SwiftUI
import Vision
import XCTest
@testable import SameWave

@MainActor
final class CaptionPresentationTests: XCTestCase {
    func testDraftTranslationAndPromotionKeepVisibleRowsInPlace() async throws {
        let store = CaptionStore()
        store.updateSource("A stable previous caption.", speaker: .mine, isFinal: true)
        store.setNativeCaption(id: 0)
        let source = "Please notify everyone on the engineering team before the design review tomorrow."
        store.updateSource(source, speaker: .remote, isFinal: false)
        let generation = try XCTUnwrap(store.beginTranslation(id: 1))
        let host = NSHostingView(rootView: CaptionsView(store: store, isListening: true))
        let window = makeWindow(host, size: NSSize(width: 600, height: 500))
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findScroll(in: host))
        let beforeHeight = scroll.documentView!.frame.height
        let before = try topPixels(host)
        try save(host, name: "caption-before-translation")
        store.applyTranslation("Notify the team.", id: 1, generation: generation)
        try await settle(host)
        try save(host, name: "caption-after-translation")
        XCTAssertEqual(scroll.documentView!.frame.height, beforeHeight, accuracy: 1)
        XCTAssertEqual(try topPixels(host), before)
        let translated = try observation("Notify the team", in: host)
        let id = store.sections[1].id
        XCTAssertEqual(store.commitReadyDrafts(at: .now.advanced(by: .seconds(1))), [id])
        try await settle(host)
        XCTAssertEqual(try observation("Notify the team", in: host).boundingBox.minY,
                       translated.boundingBox.minY, accuracy: 0.003)
        XCTAssertEqual(scroll.documentView!.frame.height, beforeHeight, accuracy: 1)
        try save(host, name: "caption-promotion")
    }

    func testReadingHistorySurvivesNewCaptionsAndResumesFollowingAtBottom() async throws {
        let store = CaptionStore()
        let historyCount = 36
        for index in 0..<historyCount {
            store.updateSource("Historical caption number \(index).", speaker: .remote, isFinal: true)
            store.setNativeCaption(id: index)
        }
        let host = NSHostingView(rootView: CaptionsView(store: store, isListening: true, hideSourceEcho: true))
        let window = makeWindow(host, size: NSSize(width: 600, height: 330))
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 100)
        XCTAssertLessThanOrEqual(scroll.documentView!.frame.height - scroll.contentView.bounds.maxY, 33)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(host)
        let readingOffset = scroll.contentView.bounds.minY
        store.updateSource("A new live caption begins", speaker: .remote, isFinal: false)
        store.setNativeCaption(id: historyCount)
        try await settle(host)
        XCTAssertEqual(scroll.contentView.bounds.minY, readingOffset, accuracy: 1)
        try save(host, name: "caption-history-reading")
        let bottom = max(0, scroll.documentView!.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(host)
        store.updateSource("A new live caption begins and continues.", speaker: .remote, isFinal: true)
        store.setNativeCaption(id: historyCount)
        store.updateSource("The following sentence remains visible.", speaker: .remote, isFinal: false)
        store.setNativeCaption(id: historyCount + 1)
        try await settle(host)
        XCTAssertLessThanOrEqual(scroll.documentView!.frame.height - scroll.contentView.bounds.maxY, 33)
        try save(host, name: "caption-following")
    }

    func testGroupedDraftKeepsEarlierWordsAndSourceAtTheSamePosition() async throws {
        let store = CaptionStore()
        store.updateSource("The earlier sentence stays stable.", speaker: .remote, isFinal: true)
        let firstGeneration = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("Earlier words remain readable.", id: 0, generation: firstGeneration)
        store.updateSource("Please notify everyone on the engineering team before the design review tomorrow.",
                           speaker: .remote, isFinal: false)
        let generation = try XCTUnwrap(store.beginTranslation(id: 1))
        XCTAssertEqual(store.paragraphLayout.paragraphs.map(\.sectionIDs), [[0, 1]])
        let host = NSHostingView(rootView: CaptionsView(store: store, isListening: true))
        let window = makeWindow(host, size: NSSize(width: 700, height: 400))
        defer { window.close() }
        try await settle(host)
        let earlier = try observation("Earlier words", in: host).boundingBox
        let source = try observation("The earlier sentence", in: host).boundingBox
        let scroll = try XCTUnwrap(findScroll(in: host))
        let height = scroll.documentView!.frame.height
        store.applyTranslation("Notify the team.", id: 1, generation: generation)
        try await settle(host)
        XCTAssertEqual(try observation("Earlier words", in: host).boundingBox.minY, earlier.minY, accuracy: 0.003)
        XCTAssertEqual(try observation("The earlier sentence", in: host).boundingBox.minY, source.minY, accuracy: 0.003)
        XCTAssertEqual(scroll.documentView!.frame.height, height, accuracy: 1)
        XCTAssertEqual(store.sections[0].generation, firstGeneration)
        XCTAssertEqual(store.commitReadyDrafts(at: .now.advanced(by: .seconds(1))), [1])
        try await settle(host)
        XCTAssertEqual(try observation("The earlier sentence", in: host).boundingBox.minY, source.minY, accuracy: 0.003)
        try save(host, name: "grouped-caption-promotion")
    }

    func testReportedHistoryFragmentsFitInOneReadableParagraph() async throws {
        let sources = ["I'd now like", "to", "quote from", "A great liberal.",
                       "Democrats.", "A friend of Ted.", "Vladimir Lenin"]
        let targets = ["现在我想", "来", "引用", "一位伟大的自由派人士。", "民主党人。", "Ted 的一位朋友。", "弗拉基米尔·列宁。"]
        let lines = zip(sources, targets).enumerated().map { index, text in
            TranscriptLine(speaker: .remote, sourceText: text.0, targetText: text.1,
                           spokenAt: Date(timeIntervalSince1970: 24_780 + Double(index)),
                           orderIndex: index, sectionId: index)
        }
        let record = MeetingRecord(startedAt: .now, endedAt: .now, languagePair: .englishToSimplifiedChinese,
                                   lineCount: lines.count, status: .ended, lines: lines)
        let host = NSHostingView(rootView: HistoryDetailView(record: record))
        let window = makeWindow(host, size: NSSize(width: 700, height: 330))
        defer { window.close() }
        try await settle(host)
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertLessThanOrEqual(scroll.documentView!.frame.height, scroll.contentView.bounds.height + 1)
        XCTAssertNotNil(try observation("I'd now like to quote from", in: host))
        XCTAssertNotNil(try observation("Vladimir Lenin", in: host))
        let time = CaptionsView.timeString(lines[0].spokenAt)
        XCTAssertEqual(try observations(in: host).filter { $0.topCandidates(1).first?.string.contains(time) == true }.count, 1)
        try save(host, name: "reported-history-paragraph")
    }

    func testLongHistoryScrollKeepsDocumentHeightAndReadingOffset() async throws {
        let source = "We can review the complete discussion after the meeting ends. "
        let target = "会议结束后，我们可以查看完整的讨论内容，核对原文和译文，并继续阅读下一段。"
        let lines = (0..<48).map { index in
            TranscriptLine(speaker: .remote,
                           sourceText: String(repeating: source, count: 1 + index % 5),
                           targetText: String(repeating: target, count: 1 + index % 7),
                           spokenAt: Date(timeIntervalSince1970: Double(index * 40)),
                           orderIndex: index, sectionId: index,
                           refinedSource: String(repeating: source, count: 1 + index % 3),
                           refinedTarget: String(repeating: target, count: 1 + index % 9))
        }
        let record = MeetingRecord(startedAt: .now, endedAt: .now, languagePair: .englishToSimplifiedChinese,
                                   lineCount: lines.count, status: .ended, lines: lines)
        let host = NSHostingView(rootView: HistoryDetailView(record: record))
        let window = makeWindow(host, size: NSSize(width: 620, height: 500))
        defer { window.close() }
        for width in [620.0, 1000.0] {
            window.setContentSize(NSSize(width: width, height: 500))
            for refined in [false, true] {
                host.rootView = HistoryDetailView(record: record, showRefined: refined)
                try await settle(host)
                let scroll = try XCTUnwrap(findScroll(in: host))
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle(host)
                let height = try XCTUnwrap(scroll.documentView).frame.height
                let bottom = height - scroll.contentView.bounds.height
                XCTAssertGreaterThan(bottom, 1000)
                for fraction in [0.1, 0.4, 0.8, 1.0, 0.7, 0.3, 0.0, 1.0, 0.0] {
                    let offset = bottom * fraction
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    try await settle(host)
                    XCTAssertEqual(scroll.documentView!.frame.height, height, accuracy: 1,
                                   "Unchanged history reflowed during scrolling (width: \(width), refined: \(refined)).")
                    XCTAssertEqual(scroll.contentView.bounds.minY, offset, accuracy: 1,
                                   "The requested reading position moved after scrolling.")
                }
            }
        }
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>, size: NSSize) -> NSWindow {
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
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

    private func observation(_ text: String, in view: NSView) throws -> VNRecognizedTextObservation {
        try XCTUnwrap(observations(in: view).first { $0.topCandidates(1).first?.string.contains(text) == true })
    }

    private func observations(in view: NSView) throws -> [VNRecognizedTextObservation] {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
        return try XCTUnwrap(request.results)
    }

    private func save(_ view: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appending(path: ".build/caption-stability", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "\(name).png"))
    }

    private func topPixels(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: image.height / 5)))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:]))
    }
}
