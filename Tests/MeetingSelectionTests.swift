import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class MeetingSelectionTests: XCTestCase {
    func testLastSelectedHistoryRestoresEvenWithNewerUnfinishedMeetings() throws {
        let (history, defaults) = try makeStorage()
        let first = try makeRecord(history, status: .ended)
        let selected = try makeRecord(history, status: .ended)
        let interrupted = try makeRecord(history, status: .recording)
        let coordinator = makeCoordinator(history, defaults)
        coordinator.selectedHistoryRecord = first
        coordinator.selectedHistoryRecord = selected

        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()

        XCTAssertEqual(reopened.selectedHistoryRecord?.id, selected.id)
        XCTAssertEqual(reopened.selectedRecordID, selected.id)
        XCTAssertNil(reopened.activeRecordID)
        XCTAssertEqual(reopened.sessionState, .idle)
        XCTAssertEqual(interrupted.meetingStatus, .paused)
    }

    func testSelectedInterruptedMeetingRestoresPausedWithItsTranscript() throws {
        let (history, defaults) = try makeStorage()
        let selected = try makeRecord(history, status: .recording)
        let newer = try makeRecord(history, status: .recording)
        defaults.set(selected.id.uuidString, forKey: "selectedMeetingID")

        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()

        XCTAssertNil(reopened.selectedHistoryRecord)
        XCTAssertEqual(reopened.activeRecordID, selected.id)
        XCTAssertEqual(reopened.selectedRecordID, selected.id)
        XCTAssertEqual(reopened.sessionState, .paused)
        XCTAssertEqual(reopened.languagePair, selected.languagePair)
        XCTAssertEqual(reopened.elapsedSeconds, 30)
        XCTAssertEqual(reopened.store.sections.first?.id, 7)
        XCTAssertEqual(reopened.store.sections.first?.sourceText, "Hello")
        XCTAssertEqual(newer.meetingStatus, .paused)
    }

    func testNoSavedSelectionRestoresMostRecentMeetingWithoutStartingCapture() throws {
        let (history, defaults) = try makeStorage()
        let interrupted = try makeRecord(history, status: .recording)
        let reopened = makeCoordinator(history, defaults)

        reopened.restoreSelection()

        XCTAssertEqual(reopened.selectedRecordID, interrupted.id)
        XCTAssertEqual(reopened.sessionState, .paused)
        XCTAssertEqual(reopened.store.sections.first?.sourceText, "Hello")
        XCTAssertEqual(defaults.string(forKey: "selectedMeetingID"), interrupted.id.uuidString)
        XCTAssertEqual(try history.unfinishedRecords().map(\.id), [interrupted.id])
        XCTAssertEqual(interrupted.meetingStatus, .paused)
    }

    func testChoosingNewMeetingPersistsANewDraftAndKeepsPreviousMeetings() async throws {
        let (history, defaults) = try makeStorage()
        let paused = try makeRecord(history, status: .paused)
        let ended = try makeRecord(history, status: .ended)
        let coordinator = makeCoordinator(history, defaults)

        await coordinator.loadSession(paused)
        await coordinator.startNewMeeting()
        let firstDraftID = try XCTUnwrap(coordinator.activeRecordID)
        XCTAssertEqual(defaults.string(forKey: "selectedMeetingID"), firstDraftID.uuidString)
        coordinator.selectedHistoryRecord = ended
        await coordinator.startNewMeeting()

        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertEqual(reopened.selectedRecordID, coordinator.activeRecordID)
        XCTAssertNotEqual(reopened.selectedRecordID, firstDraftID)
        XCTAssertEqual(reopened.workspaceRecord?.meetingStatus, .draft)
        XCTAssertEqual(reopened.sessionState, .idle)
        XCTAssertTrue(reopened.store.sections.isEmpty)
        XCTAssertNotNil(try history.record(id: paused.id))
        XCTAssertNotNil(try history.record(id: ended.id))
    }

    func testMissingOrInvalidSavedSelectionLeavesEmptyStoreUnselected() throws {
        let (history, defaults) = try makeStorage()
        let deleted = try makeRecord(history, status: .ended)
        let deletedID = deleted.id
        try history.delete(deleted)

        for value in [deletedID.uuidString, "not-a-uuid"] {
            defaults.set(value, forKey: "selectedMeetingID")
            let reopened = makeCoordinator(history, defaults)
            reopened.restoreSelection()

            XCTAssertNil(reopened.selectedRecordID)
            XCTAssertEqual(reopened.sessionState, .idle)
            XCTAssertNil(defaults.string(forKey: "selectedMeetingID"))
        }
    }

    func testMissingOrInvalidSavedSelectionChoosesMostRecentExistingMeeting() throws {
        let (history, defaults) = try makeStorage()
        let older = try history.createDraft(languagePair: .englishToEnglish, now: Date(timeIntervalSince1970: 100))
        let latest = try history.createDraft(languagePair: .englishToEnglish, now: Date(timeIntervalSince1970: 200))
        for value in [UUID().uuidString, "not-a-uuid"] {
            defaults.set(value, forKey: "selectedMeetingID")
            let reopened = makeCoordinator(history, defaults)
            reopened.restoreSelection()

            XCTAssertEqual(reopened.selectedRecordID, latest.id)
            XCTAssertEqual(reopened.workspaceRecord?.meetingStatus, .draft)
            XCTAssertEqual(reopened.sessionState, .idle)
            XCTAssertEqual(defaults.string(forKey: "selectedMeetingID"), latest.id.uuidString)
            XCTAssertNotNil(try history.record(id: older.id))
        }
    }

    func testDeletingSelectedDraftSelectsLatestHistoryAndPersistsIt() async throws {
        let (history, defaults) = try makeStorage()
        _ = try history.createDraft(languagePair: .englishToEnglish, now: Date(timeIntervalSince1970: 100))
        let latest = try makeRecord(history, status: .ended)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.startNewMeeting()
        let draft = try XCTUnwrap(coordinator.workspaceRecord)
        let deletedID = draft.id

        coordinator.delete(draft)

        XCTAssertNil(try history.record(id: deletedID))
        XCTAssertEqual(coordinator.selectedHistoryRecord?.id, latest.id)
        XCTAssertNil(coordinator.activeRecordID)
        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertTrue(coordinator.store.sections.isEmpty)
        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertEqual(reopened.selectedRecordID, latest.id)
    }

    func testDeletingSelectedDraftSelectsAnotherDraftWithoutCreatingOne() async throws {
        let (history, defaults) = try makeStorage()
        let remaining = try history.createDraft(languagePair: .simplifiedChineseToSimplifiedChinese)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.startNewMeeting()
        coordinator.delete(try XCTUnwrap(coordinator.workspaceRecord))

        XCTAssertEqual(coordinator.workspaceRecord?.id, remaining.id)
        XCTAssertEqual(coordinator.languagePair, remaining.languagePair)
        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertEqual(try history.unfinishedRecords().map(\.id), [remaining.id])
    }

    func testDeletingSelectedHistoryRestoresPausedMeetingAndItsTranscript() throws {
        let (history, defaults) = try makeStorage()
        let paused = try makeRecord(history, status: .paused)
        let selected = try makeRecord(history, status: .ended)
        let coordinator = makeCoordinator(history, defaults)
        coordinator.selectedHistoryRecord = selected

        coordinator.delete(selected)

        XCTAssertEqual(coordinator.activeRecordID, paused.id)
        XCTAssertNil(coordinator.selectedHistoryRecord)
        XCTAssertEqual(coordinator.sessionState, .paused)
        XCTAssertEqual(coordinator.elapsedSeconds, 30)
        XCTAssertEqual(coordinator.store.sections.first?.sourceText, "Hello")
        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertEqual(reopened.activeRecordID, paused.id)
    }

    func testDeletingLastDraftLeavesEmptyWorkspaceUntilNewMeetingIsChosen() async throws {
        let (history, defaults) = try makeStorage()
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.startNewMeeting()
        coordinator.delete(try XCTUnwrap(coordinator.workspaceRecord))

        XCTAssertNil(coordinator.workspaceRecord)
        XCTAssertNil(coordinator.selectedRecordID)
        XCTAssertNil(defaults.string(forKey: "selectedMeetingID"))
        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertTrue(coordinator.store.sections.isEmpty)
        XCTAssertNil(try history.mostRecentRecord())
        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertNil(reopened.selectedRecordID)

        await reopened.startNewMeeting()
        XCTAssertEqual(reopened.workspaceRecord?.meetingStatus, .draft)
    }

    func testDeletingLastEndedMeetingClearsRetainedLiveTranscript() async throws {
        let (history, defaults) = try makeStorage()
        let record = try makeRecord(history, status: .paused)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.loadSession(record)
        await coordinator.stop()
        XCTAssertTrue(coordinator.store.hasContent)

        coordinator.delete(record)

        XCTAssertNil(coordinator.workspaceRecord)
        XCTAssertFalse(coordinator.store.hasContent)
        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertNil(try history.mostRecentRecord())
    }

    func testSwitchingMountedMeetingsPersistsSelectionWithoutAHistorySelectionChange() async throws {
        let (history, defaults) = try makeStorage()
        let first = try makeRecord(history, status: .paused)
        let second = try makeRecord(history, status: .paused)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.loadSession(first)
        await coordinator.loadSession(second)

        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()

        XCTAssertNil(coordinator.selectedHistoryRecord)
        XCTAssertEqual(reopened.activeRecordID, second.id)
        XCTAssertEqual(reopened.sessionState, .paused)
    }

    func testViewingHistoryTakesPrecedenceOverMountedMeetingOnReopen() async throws {
        let (history, defaults) = try makeStorage()
        let paused = try makeRecord(history, status: .paused)
        let ended = try makeRecord(history, status: .ended)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.loadSession(paused)
        coordinator.selectedHistoryRecord = ended
        coordinator.persistNow()

        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertEqual(reopened.selectedHistoryRecord?.id, ended.id)
        XCTAssertNil(reopened.activeRecordID)

        coordinator.selectedHistoryRecord = nil
        let reopenedLive = makeCoordinator(history, defaults)
        reopenedLive.restoreSelection()
        XCTAssertEqual(reopenedLive.activeRecordID, paused.id)
    }

    func testDeletingOtherHistoryKeepsSelectionAndDeletingSelectedHistoryClearsIt() throws {
        let (history, defaults) = try makeStorage()
        let selected = try makeRecord(history, status: .ended)
        let other = try makeRecord(history, status: .ended)
        let coordinator = makeCoordinator(history, defaults)
        coordinator.selectedHistoryRecord = selected

        coordinator.delete(other)
        XCTAssertEqual(coordinator.selectedRecordID, selected.id)
        XCTAssertEqual(defaults.string(forKey: "selectedMeetingID"), selected.id.uuidString)
        coordinator.delete(selected)

        XCTAssertNil(coordinator.selectedRecordID)
        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertNil(reopened.selectedRecordID)
    }

    func testStoppingMeetingKeepsFinishedHistorySelectedOnReopen() async throws {
        let (history, defaults) = try makeStorage()
        let record = try makeRecord(history, status: .paused)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.loadSession(record)

        await coordinator.stop()

        XCTAssertEqual(coordinator.selectedHistoryRecord?.id, record.id)
        XCTAssertNil(coordinator.activeRecordID)
        XCTAssertEqual(record.meetingStatus, .ended)
        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertEqual(reopened.selectedHistoryRecord?.id, record.id)
    }

    func testStoppingEmptyMeetingRetainsWorkspaceOnReopen() async throws {
        let (history, defaults) = try makeStorage()
        let record = try history.createDraft(languagePair: .englishToEnglish)
        let id = record.id
        try history.setStatus(record, .paused)
        let coordinator = makeCoordinator(history, defaults)
        await coordinator.loadSession(record)

        await coordinator.stop()

        XCTAssertEqual(coordinator.selectedRecordID, id)
        XCTAssertNotNil(try history.record(id: id))
        let reopened = makeCoordinator(history, defaults)
        reopened.restoreSelection()
        XCTAssertEqual(reopened.selectedRecordID, id)
        XCTAssertEqual(reopened.sessionState, .idle)
    }

    private func makeStorage() throws -> (MeetingHistoryStore, UserDefaults) {
        let history = try MeetingHistoryStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "MeetingSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (history, defaults)
    }

    private func makeCoordinator(_ history: MeetingHistoryStore, _ defaults: UserDefaults) -> CaptureCoordinator {
        let coordinator = CaptureCoordinator(
            speechVocabularySettings: SpeechVocabularySettings(defaults: defaults), defaults: defaults
        )
        coordinator.history = history
        return coordinator
    }

    private func makeRecord(_ history: MeetingHistoryStore, status: MeetingStatus) throws -> MeetingRecord {
        let record = try history.createDraft(languagePair: .englishToEnglish)
        var section = Section(id: 7, speaker: .remote)
        section.committedSource = ["Hello"]
        try history.sync(
            record: record, sections: [section],
            endedAt: record.startedAt.addingTimeInterval(30), status: status
        )
        return record
    }
}
