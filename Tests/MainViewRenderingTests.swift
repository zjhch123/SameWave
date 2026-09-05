import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class MainViewRenderingTests: XCTestCase {
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
            .environment(SettingsNavigation())
            .defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await Task.yield()
        try capture(host, name: "English new meeting at minimum window size")

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
