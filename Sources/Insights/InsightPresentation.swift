import Foundation

/// Reading state belongs to one card, not to the inspector's entire timeline.
struct InsightCardReadingState {
    var timeline = InsightTimelineSelection()
    var conclusionExpanded = true
}

extension InsightKey {
    var pointsExpansionStorageKey: String { "insightPointsExpanded.\(meetingID).\(definitionID)" }
}

/// Allocate decorative colors once per identity; editing or removing peers never
/// reassigns an existing card. No color semantics enter the persisted AI model.
struct InsightCardPalette {
    private(set) var slots: [UUID: Int] = [:]

    mutating func include(_ ids: [UUID]) {
        for id in ids where slots[id] == nil { slots[id] = slots.count % 4 }
    }
}

extension MeetingRecord {
    /// Overview is created with the draft. New user definitions appear above it,
    /// without tying priority to an editable title or changing scheduling order.
    var insightReadingOrder: [InsightDefinition] { orderedDefinitions.reversed() }

    var archivedInsightConfigurations: [InsightConfiguration] {
        var seen = Set(definitions.map(\.id) + [InsightConfiguration.summary.id])
        return insightSnapshots.sorted { $0.requestedAt > $1.requestedAt }.compactMap { snapshot in
            guard seen.insert(snapshot.definitionID).inserted else { return nil }
            return InsightConfiguration(id: snapshot.definitionID, title: snapshot.definitionTitle,
                                        prompt: "", scope: .cumulative)
        }
    }
}
