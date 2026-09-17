import AppKit
import SwiftUI
import XCTest
@testable import SameWave

@MainActor
final class MainWindowPresentationTests: XCTestCase {
    func testSwiftUIModeChangesPreserveMountedSessionAndTranslationOwner() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let settings = AISettings(defaults: defaults)
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
        coordinator.history = history
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.setStatus(record, .paused)
        await coordinator.loadSession(record)
        coordinator.store.updateSource("Retained speech", speaker: .remote, isFinal: false)
        let sections = coordinator.store.sections
        let bridge = coordinator.translation
        let revision = bridge.revision
        let presentation = MainWindowPresentation(coordinator: coordinator)
        let view = MainView(coordinator: coordinator, presentation: presentation)
            .modelContainer(history.container).environment(settings)
            .environment(Phase2Fixture.settingsNavigation(settings, defaults: defaults))
            .defaultAppStorage(defaults)
        let host = NSHostingView(rootView: view)
        let window = makeWindow()
        window.contentView = host
        window.orderFront(nil)
        defer { presentation.isSimpleMode = false; window.close() }
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        try await Phase2Fixture.waitUntil { presentation.hasMainWindow }
        let frame = window.frame

        for _ in 0..<2 {
            presentation.isSimpleMode = true
            try await Phase2Fixture.waitUntil { presentation.panel?.isVisible == true && !window.isVisible }
            XCTAssertTrue(window.contentView === host)
            XCTAssertEqual(window.frame, frame)
            presentation.isSimpleMode = false
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.frame, frame)
        }
        XCTAssertEqual(coordinator.sessionState, .paused)
        XCTAssertEqual(coordinator.selectedRecordID, record.id)
        XCTAssertEqual(coordinator.store.sections, sections)
        XCTAssertTrue(coordinator.translation === bridge)
        XCTAssertEqual(coordinator.translation.revision, revision)
        XCTAssertEqual(try history.unfinishedRecords().count, 1)

        presentation.isSimpleMode = true
        XCTAssertFalse(window.isVisible)
        await coordinator.stop()
        try await Phase2Fixture.waitUntil { !presentation.isSimpleMode && window.isVisible }
        XCTAssertFalse(try XCTUnwrap(presentation.panel).isVisible)
        XCTAssertFalse(presentation.canEnterSimpleMode)
        XCTAssertTrue(window.contentView === host)
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(record.meetingStatus, .ended)
        XCTAssertEqual(coordinator.selectedHistoryRecord?.id, record.id)
        XCTAssertTrue(coordinator.translation === bridge)
        presentation.isSimpleMode = true
        XCTAssertFalse(presentation.isSimpleMode)
        XCTAssertTrue(window.isVisible)
    }

    func testSimpleModeRejectsEmptyPreparationAndEndedMeetings() async throws {
        let coordinator = makeCoordinator()
        let history = try Phase2Fixture.history()
        coordinator.history = history
        let presentation = MainWindowPresentation(coordinator: coordinator)
        let window = makeWindow()
        defer { presentation.isSimpleMode = false; window.close() }

        XCTAssertFalse(presentation.canEnterSimpleMode)
        presentation.isSimpleMode = true
        XCTAssertFalse(presentation.isSimpleMode)
        presentation.attach(to: window)
        XCTAssertNil(presentation.panel)

        let record = try history.createDraft(languagePair: .englishToEnglish)
        await coordinator.loadSession(record)
        XCTAssertEqual(coordinator.workspaceRecord?.meetingStatus, .draft)
        XCTAssertFalse(presentation.canEnterSimpleMode)
        presentation.isSimpleMode = true
        XCTAssertFalse(presentation.isSimpleMode)
        XCTAssertNil(presentation.panel)

        try history.finish(record, sections: [], endedAt: .now)
        await coordinator.openHistory(record)
        XCTAssertEqual(coordinator.selectedHistoryRecord?.id, record.id)
        XCTAssertFalse(presentation.canEnterSimpleMode)
        presentation.isSimpleMode = true
        XCTAssertFalse(presentation.isSimpleMode)
        XCTAssertNil(presentation.panel)
    }

    func testEndingBeforeWindowAttachmentDiscardsRequestedSimpleMode() async throws {
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        let window = makeWindow()
        defer { presentation.isSimpleMode = false; window.close() }
        XCTAssertTrue(presentation.canEnterSimpleMode)
        presentation.isSimpleMode = true
        await coordinator.stop()
        presentation.attach(to: window)
        XCTAssertFalse(presentation.isSimpleMode)
        XCTAssertNil(presentation.panel)
    }

    func testPanelFloatsWithoutChangingTheMainWindowAndCloseReturns() async throws {
        let window = makeWindow()
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        defer { presentation.isSimpleMode = false; window.close() }
        let frame = window.frame
        let behavior = window.collectionBehavior
        presentation.attach(to: window)
        presentation.isSimpleMode = true
        let panel = try XCTUnwrap(presentation.panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(window.collectionBehavior, behavior)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertNil(panel.standardWindowButton(.closeButton))
        XCTAssertNil(panel.standardWindowButton(.miniaturizeButton))
        XCTAssertNil(panel.standardWindowButton(.zoomButton))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.alphaValue, 1)
        XCTAssertEqual(panel.minSize.width, 440)
        XCTAssertLessThanOrEqual(panel.minSize.height, 180)
        XCTAssertTrue(panel.validateUserInterfaceItem(NSMenuItem(title: "Close",
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")))
        panel.performClose(nil)
        XCTAssertFalse(presentation.isSimpleMode)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame, frame)
    }

    func testRepeatedUpdatesAndModeSwitchesKeepPanelHostAndUserPosition() async throws {
        let window = makeWindow()
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        defer { presentation.isSimpleMode = false; window.close() }
        presentation.attach(to: window)
        presentation.isSimpleMode = true
        let panel = try XCTUnwrap(presentation.panel)
        let host = try XCTUnwrap(panel.contentView)
        var moved = panel.frame
        moved.origin.x += 15
        moved.origin.y += 20
        moved.size.width += 30
        panel.setFrame(moved, display: false)
        presentation.attach(to: window)
        XCTAssertEqual(panel.frame, moved)
        presentation.isSimpleMode = false
        presentation.isSimpleMode = true
        XCTAssertTrue(presentation.panel === panel)
        XCTAssertTrue(panel.contentView === host)
        XCTAssertEqual(panel.frame, moved)
    }

    func testLongCaptionsKeepTheNativePanelAtItsMinimumSize() async throws {
        let window = makeWindow()
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        coordinator.sourceLanguage = .english
        coordinator.targetLanguage = .simplifiedChinese
        defer { presentation.isSimpleMode = false; window.close() }
        presentation.attach(to: window)
        presentation.isSimpleMode = true
        let panel = try XCTUnwrap(presentation.panel)
        let minimum = NSSize(width: 440, height: 180)
        panel.setContentSize(minimum)
        coordinator.store.restore(sections: [(id: 0, speaker: .remote, source: "Original speech",
            target: String(repeating: "A long translated sentence. ", count: 40), startedAt: .now)])
        await Task.yield()
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.frame.size, minimum)
        XCTAssertLessThanOrEqual(panel.minSize.height, 180)
        presentation.isSimpleMode = false
        presentation.isSimpleMode = true
        XCTAssertEqual(panel.frame.size, minimum)
    }

    func testModeSelectedBeforeMainWindowAttaches() async throws {
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        let window = makeWindow()
        defer { presentation.isSimpleMode = false; window.close() }
        presentation.isSimpleMode = true
        XCTAssertNil(presentation.panel)
        presentation.attach(to: window)
        XCTAssertTrue(try XCTUnwrap(presentation.panel).isVisible)
        XCTAssertFalse(window.isVisible)
    }

    func testConfiguratorAttachesWhenMountedAfterItsInitialUpdate() async throws {
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        let host = NSHostingView(rootView: MainWindowConfigurator(presentation: presentation))
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertFalse(presentation.hasMainWindow)
        let window = makeWindow()
        defer { presentation.isSimpleMode = false; window.close() }
        window.contentView = host
        window.orderFront(nil)
        try await Phase2Fixture.waitUntil { presentation.hasMainWindow }
        presentation.isSimpleMode = true
        XCTAssertTrue(try XCTUnwrap(presentation.panel).isVisible)
        XCTAssertFalse(window.isVisible)
    }

    func testExplicitFullWindowActionReopensHiddenWindowWithoutRecreatingIt() async throws {
        let window = makeWindow()
        let coordinator = try await makePausedCoordinator()
        let presentation = MainWindowPresentation(coordinator: coordinator)
        defer { presentation.isSimpleMode = false; window.close() }
        XCTAssertFalse(presentation.hasMainWindow)
        presentation.attach(to: window)
        XCTAssertTrue(presentation.hasMainWindow)
        let frame = window.frame
        window.orderOut(nil)
        presentation.showFullWindow()
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(presentation.isSimpleMode)
        XCTAssertNil(presentation.panel)
        XCTAssertEqual(window.frame, frame)

        presentation.isSimpleMode = true
        window.orderFront(nil)
        presentation.isSimpleMode = true
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(try XCTUnwrap(presentation.panel).isVisible)
        presentation.showFullWindow()
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(presentation.isSimpleMode)
    }

    private func makeCoordinator() -> CaptureCoordinator {
        let defaults = Phase2Fixture.defaults(self)
        return CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults)
    }

    private func makePausedCoordinator() async throws -> CaptureCoordinator {
        let coordinator = makeCoordinator()
        let history = try Phase2Fixture.history()
        coordinator.history = history
        let record = try history.createDraft(languagePair: .englishToEnglish)
        try history.setStatus(record, .paused)
        await coordinator.loadSession(record)
        return coordinator
    }

    private func makeWindow() -> NSWindow {
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 30, y: screen.minY + 30, width: 1000, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}
