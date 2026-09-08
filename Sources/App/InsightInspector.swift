import SwiftUI

struct InsightInspector: View {
    let coordinator: CaptureCoordinator
    @Environment(AISettings.self) private var aiSettings
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @State private var palettes: [UUID: InsightCardPalette] = [:]

    private var record: MeetingRecord? { coordinator.workspaceRecord }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI Insights").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { settingsNavigation.openAISettings() } label: {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).help("AI Service Settings").accessibilityLabel("AI Service Settings")
            }.frame(height: 48).padding(.horizontal, 16)
            Divider()
            if let record {
                ScrollView {
                    // Measure expanded cards together so scrolling never revises estimated heights.
                    VStack(alignment: .leading, spacing: 12) {
                        if !aiSettings.isConfigured {
                            Button("Configure AI Services") { settingsNavigation.openAISettings() }
                                .font(.caption)
                            Text("Saved results are available offline.")
                                .font(.system(size: 11)).foregroundStyle(CaptionsView.muted)
                        }
                        if record.definitions.isEmpty {
                            Text("Add an insight in Meeting Preparation.")
                                .font(.callout).foregroundStyle(CaptionsView.muted)
                        } else {
                            customInsightsHeader(record)
                        }
                        ForEach(record.insightReadingOrder) { definition in
                            card(definition.configuration, record: record,
                                 tone: palettes[record.id]?.slots[definition.id] ?? 0,
                                 automatic: definition.automaticallyUpdates)
                        }
                        // Removing a definition must not hide a generated value that failed to save.
                        ForEach(orphanedUnsavedConfigurations(record), id: \.id) { configuration in
                            card(configuration, record: record, allowsGeneration: false)
                        }
                        if record.meetingStatus == .ended {
                            card(.summary, record: record)
                        }
                    }.padding(12)
                }.id(record.id)
            } else {
                Text("No meeting selected.\nYour insights will appear here.")
                    .font(.system(size: 13)).foregroundStyle(CaptionsView.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CaptionsView.bg)
        .onAppear(perform: ensurePalette)
        .onChange(of: record?.id) { _, _ in ensurePalette() }
        .onChange(of: record?.orderedDefinitions.map(\.id)) { _, _ in ensurePalette() }
    }

    private func customInsightsHeader(_ record: MeetingRecord) -> some View {
        let generating = coordinator.insights?.batchMeetingIDs.contains(record.id) == true
        return HStack(alignment: .firstTextBaseline) {
            Text("Custom Insights").font(.system(size: 11, weight: .medium))
                .foregroundStyle(CaptionsView.muted)
            Spacer(minLength: 0)
            if generating { ProgressView().controlSize(.mini) }
            Button(generating ? String(localized: "Stop") : String(localized: "Generate")) {
                if generating { coordinator.insights?.cancelBatch(record.id) }
                else { coordinator.generateAllInsights() }
            }
            .controlSize(.small)
            .disabled(!generating && (!aiSettings.isConfigured || coordinator.isTransitioning
                || coordinator.insights?.canGenerateAll(record) != true))
            .help(generating ? String(localized: "Stop generating custom insights") : String(localized: "Generate all custom insights"))
            .accessibilityLabel(generating ? String(localized: "Stop all custom insights") : String(localized: "Generate all custom insights"))
        }
    }

    private func card(_ configuration: InsightConfiguration, record: MeetingRecord,
                      tone: Int = 3, automatic: Bool = false, allowsGeneration: Bool = true) -> some View {
        let key = InsightKey(meetingID: record.id, definitionID: configuration.id)
        let isSummary = configuration.id == InsightConfiguration.summary.id
        return InsightResultCard(
            meetingID: record.id,
            configuration: configuration,
            snapshots: record.insightSnapshots.filter { $0.definitionID == configuration.id },
            tone: tone, state: coordinator.insights?.states[key],
            unsaved: coordinator.insights?.unsaved.values.filter {
                $0.input.meetingID == record.id && $0.input.configuration.id == configuration.id
            }.sorted { $0.input.requestedAt < $1.input.requestedAt } ?? [],
            canGenerate: aiSettings.isConfigured && !coordinator.isTransitioning
                && coordinator.insights?.batchMeetingIDs.contains(record.id) != true
                && record.meetingStatus != .draft && (!isSummary || record.meetingStatus == .ended),
            automatic: automatic,
            emptyMessage: isSummary ? String(localized: "Generate a summary of the complete meeting.")
                : (record.meetingStatus == .draft ? String(localized: "Ready when the conversation starts.")
                   : String(localized: "No saved insight yet. Generate when you’re ready.")),
            generate: allowsGeneration ? { coordinator.generateInsight(configuration, summary: isSummary) } : nil,
            stop: { coordinator.insights?.cancel(key) },
            retrySave: { coordinator.insights?.retrySave($0) }
        )
    }

    private func ensurePalette() {
        guard let record else { return }
        palettes[record.id, default: InsightCardPalette()].include(record.orderedDefinitions.map(\.id))
    }

    private func orphanedUnsavedConfigurations(_ record: MeetingRecord) -> [InsightConfiguration] {
        var seen = Set(record.definitions.map(\.id) + [InsightConfiguration.summary.id])
        return (coordinator.insights?.unsaved.values.sorted { $0.input.requestedAt < $1.input.requestedAt } ?? [])
            .filter { $0.input.meetingID == record.id }
            .compactMap { value in
                seen.insert(value.input.configuration.id).inserted ? value.input.configuration : nil
            }
    }
}
