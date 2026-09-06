import Foundation
import SwiftData

@Model
final class InsightSnapshot {
    @Attribute(.unique) var id: UUID
    var definitionID: UUID
    var definitionTitle: String
    var kind: String
    var requestedAt: Date
    var completedAt: Date
    var payload: Data
    var record: MeetingRecord?

    init(_ value: InsightSnapshotValue) throws {
        id = value.id
        definitionID = value.input.configuration.id
        definitionTitle = value.input.configuration.title
        kind = value.input.kind.rawValue
        requestedAt = value.input.requestedAt
        completedAt = value.completedAt
        payload = try JSONEncoder().encode(value)
    }

    func decoded() throws -> InsightSnapshotValue {
        try JSONDecoder().decode(InsightSnapshotValue.self, from: payload)
    }
}

/// Selection is independent of incoming history. Only an explicit Latest action clears it.
struct InsightTimelineSelection {
    var snapshotID: UUID?

    func selected(from snapshots: [InsightSnapshot]) -> InsightSnapshot? {
        if let snapshotID { return snapshots.first { $0.id == snapshotID } }
        return snapshots.max { $0.requestedAt < $1.requestedAt }
    }
}

extension MeetingHistoryStore {
    /// The value survives rollback in the engine. Retrying a save never calls the provider.
    func appendInsight(_ value: InsightSnapshotValue) throws {
        guard let record = try record(id: value.input.meetingID) else {
            throw LLMError.invalidRequest("This meeting has been deleted.")
        }
        guard !record.insightSnapshots.contains(where: { $0.id == value.id }) else { return }
        let snapshot = try InsightSnapshot(value)
        snapshot.record = record
        context.insert(snapshot)
        try save()
    }
}
