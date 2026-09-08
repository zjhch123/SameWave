import SwiftUI

/// One stable view identity owns one definition's reading state.
struct InsightResultCard: View {
    let meetingID: UUID
    let configuration: InsightConfiguration
    let snapshots: [InsightSnapshot]
    var tone = 3
    var state: InsightEngine.State?
    var unsaved: [InsightSnapshotValue] = []
    var canGenerate = false
    var automatic = false
    var emptyMessage = String(localized: "No saved insight yet. Generate from the conversation so far.")
    var generate: (() -> Void)?
    var stop: (() -> Void)?
    var retrySave: ((UUID) -> Void)?
    @State private var reading = InsightCardReadingState()

    private var orderedSnapshots: [InsightSnapshot] { snapshots.sorted { $0.requestedAt > $1.requestedAt } }
    private var selectedSnapshot: InsightSnapshot? { reading.timeline.selected(from: snapshots) }
    private var isGenerating: Bool { state == .generating }
    private var isFailed: Bool { if case .failed = state { true } else { false } }
    var body: some View {
        let selection = selectedSnapshot.map { snapshot in Result { try snapshot.decoded() } }
        let selectedSummary = if case .success(let value)? = selection { value.result.summary } else { nil as MeetingSummary? }
        let usesSections = configuration.id == InsightConfiguration.summary.id
            || selectedSummary != nil
            || unsaved.contains { $0.result.summary != nil }
        VStack(alignment: .leading, spacing: 12) {
            if usesSections { sections(selection: selection) } else { card(selection: selection) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(configuration.displayTitle)
    }

    private func sections(selection: Result<InsightSnapshotValue, Error>?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(configuration.displayTitle).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CaptionsView.muted)
                Spacer(minLength: 0)
                generateButton
            }
            if state != nil || automatic { generationStatus(usesSections: true) }
            if selectedSnapshot != nil { historyFooter }
            ForEach(unsaved) { value in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Unsaved result").foregroundStyle(.orange)
                        Spacer(minLength: 0)
                        Button("Retry Save") { retrySave?(value.id) }
                    }.font(.caption)
                    versionContent(value)
                }
            }
            if let selection {
                savedContent(selection)
            } else if unsaved.isEmpty {
                MeetingSummaryCards(summary: nil)
            }
        }
    }

    @ViewBuilder private var generateButton: some View {
        if let generate {
            Button(action: generate) {
                if configuration.id == InsightConfiguration.summary.id {
                    Text(isFailed ? String(localized: "Retry") : String(localized: "Generate"))
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                }
            }
                .controlSize(.small)
                .disabled(!canGenerate || isGenerating || state == .queued || !unsaved.isEmpty)
                .help(isFailed ? String(localized: "Retry \(configuration.displayTitle)")
                      : String(localized: "Regenerate \(configuration.displayTitle)"))
                .accessibilityLabel("Generate \(configuration.displayTitle)")
        }
    }

    private func card(selection: Result<InsightSnapshotValue, Error>?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(configuration.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                generateButton
            }
            generationStatus(usesSections: false)
            ForEach(unsaved) { value in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unsaved result").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    versionContent(value)
                    Button("Retry Save") { retrySave?(value.id) }.font(.caption)
                }
            }
            if let selection {
                savedContent(selection)
                Divider().overlay(CaptionsView.borderSoft)
                historyFooter
            } else if unsaved.isEmpty {
                Text(isGenerating || state == .queued ? String(localized: "Your insight will appear here.") : emptyMessage)
                    .foregroundStyle(CaptionsView.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(CaptionsView.fg)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightCardPalette.fill(tone), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func savedContent(_ selection: Result<InsightSnapshotValue, Error>) -> some View {
        switch selection {
        case .success(let value): versionContent(value)
        case .failure:
            Text("This saved result could not be decoded. Its stored data has been retained.")
                .font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder private func versionContent(_ value: InsightSnapshotValue) -> some View {
        if let summary = value.result.summary {
            MeetingSummaryCards(summary: summary)
        } else {
            resultContent(value).font(.system(size: 13)).foregroundStyle(CaptionsView.fg)
        }
    }

    @ViewBuilder private func generationStatus(usesSections: Bool) -> some View {
        switch state {
        case .queued:
            HStack {
                Text("Queued")
                Spacer(minLength: 0)
                if let stop { Button("Stop", action: stop).buttonStyle(.plain) }
            }.font(.system(size: 10)).foregroundStyle(CaptionsView.muted)
        case .generating:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Updating…")
                Spacer(minLength: 0)
                if let stop { Button("Stop", action: stop).buttonStyle(.plain) }
            }.font(.system(size: 10)).foregroundStyle(CaptionsView.muted)
        case .failed(let message), .unsaved(let message):
            Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        case .cancelled:
            Text("Update stopped").font(.system(size: 10)).foregroundStyle(CaptionsView.muted)
        case .saved, .none:
            if !usesSections || automatic {
                Text(generate == nil ? String(localized: "Saved history") : (automatic ? String(localized: "Automatic updates on") : String(localized: "Manual")))
                    .font(.system(size: 10)).foregroundStyle(CaptionsView.muted)
            }
        }
    }

    private func resultContent(_ value: InsightSnapshotValue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reading.conclusionExpanded || value.result.conclusion.count <= 240
                 ? value.result.conclusion : String(value.result.conclusion.prefix(240)) + "…")
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if value.result.conclusion.count > 240 {
                Button(reading.conclusionExpanded ? String(localized: "Show less") : String(localized: "Read full conclusion")) {
                    reading.conclusionExpanded.toggle()
                }.buttonStyle(.plain).font(.caption).foregroundStyle(CaptionsView.accent)
            }
            if !value.result.points.isEmpty {
                InsightKeyPoints(key: InsightKey(meetingID: meetingID, definitionID: configuration.id),
                                 points: value.result.points)
            }
        }
    }

    private var historyFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Menu {
                    Button("Latest") { reading.timeline.snapshotID = nil }
                    Divider()
                    ForEach(Array(orderedSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                        Button("v\(snapshots.count - index) · \(snapshot.requestedAt.formatted(date: .abbreviated, time: .standard))") {
                            reading.timeline.snapshotID = snapshot.id
                        }
                    }
                } label: {
                    Text(historyLabel).font(.system(size: 10)).lineLimit(1)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("History for \(configuration.displayTitle)")
                Spacer(minLength: 0)
            }
            if reading.timeline.snapshotID != nil {
                if selectedSnapshot?.id != orderedSnapshots.first?.id {
                    Text("Newer result available").font(.system(size: 10)).foregroundStyle(CaptionsView.muted)
                }
                Button("View Latest") { reading.timeline.snapshotID = nil }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(CaptionsView.accent)
            }
        }
    }

    private var historyLabel: String {
        guard let id = reading.timeline.snapshotID,
              let index = orderedSnapshots.firstIndex(where: { $0.id == id }) else {
            return String(localized: "Latest · v\(snapshots.count)")
        }
        return String(localized: "Viewing v\(snapshots.count - index)")
    }
}

private struct InsightKeyPoints: View {
    let points: [String]
    @AppStorage private var expanded: Bool

    init(key: InsightKey, points: [String]) {
        self.points = points
        _expanded = AppStorage(wrappedValue: true, key.pointsExpansionStorageKey)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 7) {
                        Text("•").foregroundStyle(CaptionsView.muted)
                        Text(point).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.top, 6)
        } label: {
            Text("\(points.count) key points")
                .font(.system(size: 11)).foregroundStyle(CaptionsView.muted)
        }
    }
}
