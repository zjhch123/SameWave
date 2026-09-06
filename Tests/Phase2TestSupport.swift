import SwiftData
import XCTest
@testable import SameWave

@MainActor
enum Phase2Fixture {
    static func history() throws -> MeetingHistoryStore {
        try MeetingHistoryStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    static func defaults(_ test: XCTestCase) -> UserDefaults {
        let name = "Phase2Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        test.addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    static func settingsNavigation(_ settings: AISettings, defaults: UserDefaults) -> SettingsNavigation {
        SettingsNavigation(aiSettings: settings, vocabularyEditor:
            VocabularyEditorStore(aiSettings: settings, settings: SpeechVocabularySettings(defaults: defaults)))
    }

    static func source(_ text: String = "Launch Friday, subject to security review.",
                       provisional: String = "") -> [InsightSource] {
        [.init(id: 1, speaker: .remote, spokenAt: Date(timeIntervalSince1970: 100),
               text: text, provisionalText: provisional)]
    }

    static func input(record: MeetingRecord, configuration: InsightConfiguration = .summary,
                      kind: InsightKind = .summary, now: Date = .now,
                      text: String = "Launch Friday, subject to security review.",
                      budget: Int = 32_768) -> InsightInput {
        InsightInput(meetingID: record.id, configuration: configuration, kind: kind,
                     requestedAt: now, elapsedSeconds: 65, sources: source(text),
                     vocabulary: ["XPay"], additionalInstructions: [], providerModel: "Test",
                     contextTokenBudget: budget)
    }

    static var summary: MeetingSummary {
        MeetingSummary(topics: ["A conditional Friday launch for XPay."],
            decisions: ["Security review must finish before launch."],
            actionItems: ["Owner unknown: complete the security review before launch."],
            openQuestions: ["Who will sign off the security review?"],
            suggestions: ["Confirm a review owner and a fallback launch date."])
    }

    static func snapshot(record: MeetingRecord, configuration: InsightConfiguration = .summary,
                         kind: InsightKind = .summary, now: Date = .now) -> InsightSnapshotValue {
        InsightSnapshotValue(id: UUID(), input: input(record: record, configuration: configuration, kind: kind, now: now),
                             completedAt: now.addingTimeInterval(1),
                             result: InsightResult(conclusion: "Launch depends on security review.",
                                                   points: [],
                                                   summary: kind == .summary ? summary : nil))
    }

    static func waitUntil(_ predicate: @MainActor () async -> Bool,
                          file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for controlled async work", file: file, line: line)
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

actor ControlledInsightProvider: LLMProvider {
    private(set) var users: [String] = []
    private(set) var peakActiveCount = 0
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    var count: Int { users.count }

    func complete(system: String, user: String, schema: LLMResponseSchema) async throws -> String {
        let index = users.count
        users.append(user)
        // Deliberately ignores cancellation to verify rejection of late responses.
        return try await withCheckedThrowingContinuation {
            pending[index] = $0
            peakActiveCount = max(peakActiveCount, pending.count)
        }
    }

    func succeed(_ index: Int, conclusion: String = "Recorded conclusion", summary: MeetingSummary? = nil) throws {
        let result = InsightResult(conclusion: conclusion, points: [], summary: summary)
        let raw = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        pending.removeValue(forKey: index)?.resume(returning: raw)
    }

    func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: LLMError.rateLimited) }
    func releaseAll() {
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
        pending.removeAll()
    }
}
