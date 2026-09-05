import SwiftData
import SwiftUI

struct InsightInspector: View {
    let coordinator: CaptureCoordinator
    @Binding var selectedRecord: MeetingRecord?
    @Environment(\.openSettings) private var openSettings
    @Environment(AISettings.self) private var aiSettings
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @Environment(\.modelContext) private var modelContext

    private enum GenerationState: Equatable {
        case idle
        case generating
        case failed(String)
    }

    @State private var generationState: GenerationState = .idle
    @State private var historyInsight: InsightResult?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(CaptionsView.borderSoft).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CaptionsView.bg)
        .onChange(of: selectedRecord?.id) { _, _ in syncSelectedRecord() }
        .onAppear { syncSelectedRecord() }
        .onDisappear { cancelGeneration() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("AI Insights")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if isGenerating { ProgressView().controlSize(.small) }
            Spacer()
            if selectedRecord != nil { generationButton }
            Button { openAISettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(CaptionsView.muted)
            }
            .buttonStyle(.plain)
            .help("AI Service Settings")
            .accessibilityLabel("AI Service Settings")
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
    }

    private var isGenerating: Bool {
        if generationState == .generating { return true }
        if selectedRecord == nil, case .generating = coordinator.insights?.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        if selectedRecord != nil {
            historyContent
        } else {
            InsightCardsView(
                result: coordinator.insights?.current ?? .empty,
                state: coordinator.insights?.state ?? .idle,
                isConfigured: aiSettings.isConfigured,
                onOpenSettings: { openAISettings() },
                centersPlaceholder: true
            )
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if !aiSettings.isConfigured {
            InsightCardsView(
                result: .empty,
                state: .idle,
                isConfigured: false,
                onOpenSettings: { openAISettings() },
                centersPlaceholder: true
            )
        } else if let historyInsight, !historyInsight.isEmpty {
            ScrollView {
                InsightCardsView(result: historyInsight, state: .done, isConfigured: true)
                    .padding(16)
            }
        } else if generationState == .generating {
            InsightCardsView(
                result: .empty,
                state: .generating,
                isConfigured: true,
                centersPlaceholder: true
            )
        } else if case .failed(let message) = generationState {
            centeredHint(message, color: CaptionsView.danger)
        } else {
            centeredHint("Use the sparkle button above to summarize topics, action items, and decisions.", color: CaptionsView.muted)
        }
    }

    private var generationButton: some View {
        let hasResult = historyInsight?.isEmpty == false
        let label = !aiSettings.isConfigured
            ? "Configure AI Services"
            : hasResult ? "Regenerate" : "Generate Insights"
        return Button {
            if aiSettings.isConfigured { generateHistoryInsight() }
            else { openAISettings() }
        } label: {
            Label(
                label,
                systemImage: hasResult ? "arrow.clockwise" : "sparkles"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CaptionsView.accent)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .disabled(generationState == .generating)
    }

    private func openAISettings() {
        settingsNavigation.openAISettings { openSettings() }
    }

    private func centeredHint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncSelectedRecord() {
        cancelGeneration()
        historyInsight = selectedRecord?.insight
        generationState = .idle
    }

    private func generateHistoryInsight() {
        guard let record = selectedRecord, let engine = coordinator.insights else { return }
        generationState = .generating
        let transcript = InsightEngine.flatten(
            lines: record.lines,
            preferringRefinedSource: true
        )
        let token = UUID()
        generationToken = token
        generationTask = Task { @MainActor in
            do {
                let result = try await engine.generateOnce(transcript: transcript)
                guard !Task.isCancelled,
                      generationToken == token,
                      selectedRecord?.id == record.id else { return }
                guard let encoded = result.encoded() else { throw LLMError.badResponse }
                record.insightJSON = encoded
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    throw error
                }
                historyInsight = result
                generationState = .idle
            } catch is CancellationError {
                return
            } catch let error as LLMError {
                guard generationToken == token else { return }
                generationState = .failed(error.errorDescription ?? "Generation failed")
            } catch {
                guard generationToken == token else { return }
                generationState = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationToken = UUID()
    }
}
