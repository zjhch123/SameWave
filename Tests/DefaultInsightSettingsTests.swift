import SwiftData
import XCTest
@testable import SameWave

@MainActor
final class DefaultInsightSettingsTests: XCTestCase {
    func testInitialOverviewAndSavedEmptyListRemainDistinct() throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = DefaultInsightSettings(defaults: defaults)
        let overview = try XCTUnwrap(settings.templates.first)
        XCTAssertEqual(settings.templates.count, 1)
        XCTAssertEqual(overview.title, String(localized: "Meeting Overview"))
        XCTAssertEqual(overview.scope, .cumulative)
        XCTAssertFalse(overview.automaticallyUpdates)
        XCTAssertNil(defaults.object(forKey: DefaultInsightSettings.storageKey))

        try settings.remove(id: overview.id)
        let reopened = DefaultInsightSettings(defaults: defaults)
        XCTAssertTrue(try reopened.templatesForNewMeeting().isEmpty)
        let history = try Phase2Fixture.history()
        let empty = try history.createDraft(languagePair: .englishToEnglish,
            insightTemplates: reopened.templatesForNewMeeting())
        XCTAssertTrue(empty.definitions.isEmpty)
    }

    func testAddingEditingAndRemovingDefaultsPersistEveryField() throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = DefaultInsightSettings(defaults: defaults)
        var item = InsightTemplate(title: "  Follow-ups  ", prompt: "\nIdentify the next steps.\n",
                                   automaticallyUpdates: true, scope: .latestExchange)
        try settings.save(item)
        item = item.normalized
        XCTAssertEqual(DefaultInsightSettings(defaults: defaults).templates.last, item)
        item.title = "Decisions"
        item.prompt = "Track decisions and corrections."
        item.automaticallyUpdates = false
        item.scope = .cumulative
        try settings.save(item)
        let reopened = DefaultInsightSettings(defaults: defaults)
        XCTAssertEqual(reopened.templates.count, 2)
        XCTAssertEqual(reopened.templates.last, item)
        try reopened.remove(id: item.id)
        XCTAssertEqual(DefaultInsightSettings(defaults: defaults).templates, Array(settings.templates.prefix(1)))
    }

    func testInvalidEditKeepsThePreviousSavedValue() throws {
        let defaults = Phase2Fixture.defaults(self)
        let settings = DefaultInsightSettings(defaults: defaults)
        let item = InsightTemplate(title: "Risks", prompt: "Find material risks.")
        try settings.save(item)
        let original = settings.templates
        let saved = defaults.data(forKey: DefaultInsightSettings.storageKey)
        var invalid = item
        invalid.prompt = " \n "
        XCTAssertThrowsError(try settings.save(invalid))
        invalid = item
        invalid.title = "\n"
        XCTAssertThrowsError(try settings.save(invalid))
        XCTAssertEqual(settings.templates, original)
        XCTAssertEqual(defaults.data(forKey: DefaultInsightSettings.storageKey), saved)
    }

    func testUnreadableDefaultsArePreservedUntilExplicitReset() throws {
        let defaults = Phase2Fixture.defaults(self)
        let item = InsightTemplate(title: "Risks", prompt: "Find risks.")
        let invalidValues: [Any] = [
            "unexpected type", Data("not JSON".utf8),
            try JSONEncoder().encode([item, item]),
            try JSONEncoder().encode([InsightTemplate(title: "", prompt: "Missing title")])
        ]
        for value in invalidValues {
            defaults.set(value, forKey: DefaultInsightSettings.storageKey)
            let settings = DefaultInsightSettings(defaults: defaults)
            XCTAssertNotNil(settings.loadError)
            XCTAssertThrowsError(try settings.templatesForNewMeeting())
            XCTAssertThrowsError(try settings.save(item))
            XCTAssertThrowsError(try settings.remove(id: item.id))
            XCTAssertEqual(defaults.object(forKey: DefaultInsightSettings.storageKey) as? NSObject, value as? NSObject)
            try settings.reset()
            XCTAssertNil(settings.loadError)
            XCTAssertEqual(try DefaultInsightSettings(defaults: defaults).templatesForNewMeeting().count, 1)
        }
    }

    func testNewMeetingsCopyCurrentDefaultsWithIndependentIdentities() async throws {
        let defaults = Phase2Fixture.defaults(self)
        let history = try Phase2Fixture.history()
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults),
                                             defaults: defaults)
        coordinator.history = history
        let settings = coordinator.defaultInsights
        let overviewID = try XCTUnwrap(settings.templates.first?.id)
        try settings.remove(id: overviewID)
        var item = InsightTemplate(title: "Follow-ups", prompt: "Identify the next steps.",
                                   automaticallyUpdates: true, scope: .latestExchange)
        try settings.save(item)
        await coordinator.startNewMeeting()
        let first = try XCTUnwrap(coordinator.workspaceRecord)
        let firstDefinition = try XCTUnwrap(first.definitions.first)
        XCTAssertNotEqual(firstDefinition.id, item.id)
        XCTAssertEqual(firstDefinition.title, item.title)
        XCTAssertEqual(firstDefinition.prompt, item.prompt)
        XCTAssertEqual(firstDefinition.configuration.scope, .latestExchange)
        XCTAssertTrue(firstDefinition.automaticallyUpdates)

        item.prompt = "Identify blockers."
        try settings.save(item)
        await coordinator.startNewMeeting()
        let second = try XCTUnwrap(coordinator.workspaceRecord)
        let secondDefinition = try XCTUnwrap(second.definitions.first)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(secondDefinition.id, firstDefinition.id)
        XCTAssertNotEqual(secondDefinition.id, item.id)
        XCTAssertEqual(firstDefinition.prompt, "Identify the next steps.")
        XCTAssertEqual(secondDefinition.prompt, "Identify blockers.")

        firstDefinition.title = "Meeting-specific title"
        firstDefinition.automaticallyUpdates = false
        try history.save()
        XCTAssertEqual(settings.templates.first, item)
        XCTAssertEqual(secondDefinition.title, "Follow-ups")
        XCTAssertTrue(secondDefinition.automaticallyUpdates)
        try settings.remove(id: item.id)
        await coordinator.loadSession(first)
        XCTAssertEqual(first.definitions.count, 1)
        XCTAssertEqual(firstDefinition.title, "Meeting-specific title")
        await coordinator.startNewMeeting()
        XCTAssertTrue(try XCTUnwrap(coordinator.workspaceRecord).definitions.isEmpty)
        XCTAssertEqual(second.definitions.count, 1)
    }

    func testBothCreationEntrypointsReportUnreadableDefaultsWithoutCreatingADraft() async throws {
        let defaults = Phase2Fixture.defaults(self)
        defaults.set(Data("broken".utf8), forKey: DefaultInsightSettings.storageKey)
        let history = try Phase2Fixture.history()
        let coordinator = CaptureCoordinator(speechVocabularySettings: SpeechVocabularySettings(defaults: defaults),
                                             defaults: defaults)
        coordinator.history = history
        await coordinator.startNewMeeting()
        XCTAssertNil(coordinator.workspaceRecord)
        XCTAssertFalse(coordinator.statusMessage.isEmpty)
        await coordinator.startGlobal()
        XCTAssertNil(coordinator.workspaceRecord)
        XCTAssertFalse(coordinator.statusMessage.isEmpty)
        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertEqual(try history.context.fetchCount(FetchDescriptor<MeetingRecord>()), 0)
    }

    func testCopiedDefaultsAndSnapshotSurviveReopenAndTemplateRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("meetings.store")
        let defaults = Phase2Fixture.defaults(self)
        let settings = DefaultInsightSettings(defaults: defaults)
        let custom = InsightTemplate(title: "Risks", prompt: "Find material risks.",
                                     automaticallyUpdates: true, scope: .latestExchange)
        try settings.save(custom)
        let id: UUID
        let definitions: [InsightTemplate]
        let snapshot: InsightSnapshotValue
        do {
            let history = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
            let record = try history.createDraft(languagePair: .englishToEnglish,
                insightTemplates: settings.templatesForNewMeeting())
            id = record.id
            definitions = record.orderedDefinitions.map(\.template)
            XCTAssertEqual(definitions.map(\.title), settings.templates.map(\.title))
            snapshot = Phase2Fixture.snapshot(record: record,
                configuration: try XCTUnwrap(record.orderedDefinitions.last).configuration, kind: .manual)
            try history.appendInsight(snapshot)
        }
        for template in settings.templates { try settings.remove(id: template.id) }
        let reopened = try MeetingHistoryStore(configuration: ModelConfiguration(url: url))
        let record = try XCTUnwrap(reopened.record(id: id))
        XCTAssertEqual(record.orderedDefinitions.map(\.template), definitions)
        XCTAssertEqual(try record.insightSnapshots.first?.decoded(), snapshot)
        XCTAssertTrue(DefaultInsightSettings(defaults: defaults).templates.isEmpty)
    }
}
