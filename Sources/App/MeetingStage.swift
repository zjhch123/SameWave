import SwiftData
import SwiftUI

struct MeetingStage: View {
    let coordinator: CaptureCoordinator
    @Binding var sidebarOpen: Bool
    @Binding var selectedRecord: MeetingRecord?
    @State private var showRefined = true
    @Environment(AISettings.self) private var aiSettings

    var body: some View {
        VStack(spacing: 0) {
            StageHeader(
                coordinator: coordinator,
                sidebarOpen: $sidebarOpen,
                selectedRecord: $selectedRecord,
                showRefined: $showRefined
            )
            .frame(height: 48)

            if let record = selectedRecord {
                HistoryDetailView(
                    record: record,
                    showRefined: showRefined && record.hasRefinement
                )
                .id(record.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coordinator.workspaceRecord == nil {
                ContentUnavailableView {
                    Label("No Meetings", systemImage: "rectangle.stack")
                } description: {
                    Text("Create a meeting to get started.")
                } actions: {
                    Button("New Meeting") { Task { await coordinator.startNewMeeting() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Group {
                        if let record = coordinator.workspaceRecord,
                           record.meetingStatus == .draft, let history = coordinator.history {
                            MeetingPreparationView(record: record, history: history,
                                editor: coordinator.vocabularyEditor(for: record, settings: aiSettings))
                                .id(record.id)
                        } else {
                            CaptionsView(
                                store: coordinator.store,
                                isListening: coordinator.isRunning,
                                statusMessage: coordinator.statusMessage,
                                hideSourceEcho: !coordinator.languagePair.needsTranslation
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MeetingControlDock(coordinator: coordinator)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(CaptionsView.bg)
    }
}

private struct StageHeader: View {
    let coordinator: CaptureCoordinator
    @Binding var sidebarOpen: Bool
    @Binding var selectedRecord: MeetingRecord?
    @Binding var showRefined: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettings.self) private var aiSettings
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @State private var saveError: String?
    @State private var showingPreparation = false
    @State private var refinementTask: Task<Void, Never>?
    @State private var titleTask: Task<Void, Never>?
    @State private var refinementToken = UUID()

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarOpen { Color.clear.frame(width: 64) }
            iconButton("sidebar.left", help: "Toggle Sidebar") { sidebarOpen.toggle() }
            if let record = coordinator.workspaceRecord, record.meetingStatus != .draft {
                iconButton("slider.horizontal.3", help: "Meeting Preparation") { showingPreparation = true }
            }

            if let record = selectedRecord {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .help(record.displayTitle)
                    Text(record.displayMetaText)
                        .font(.system(size: 11))
                        .foregroundStyle(CaptionsView.meta)
                        .help(record.displayMetaText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, 8)

                if record.hasRefinement {
                    Picker("", selection: $showRefined) {
                        Text("Refined").tag(true)
                        Text("Original").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.trailing, 4)
                }
                refineButton(record)
                iconButton("square.and.arrow.up", help: "Export Meeting") {
                    TranscriptExporter.exportRecord(record)
                }
            } else if coordinator.workspaceRecord != nil {
                Spacer()
                if coordinator.isRunning || !coordinator.statusMessage.isEmpty {
                    liveStatus
                }
                Spacer()
                iconButton("square.and.arrow.up", help: "Export Transcript") {
                    TranscriptExporter.exportWithPanel(
                        store: coordinator.store,
                        showsSourceEcho: coordinator.languagePair.needsTranslation
                    )
                }
                .disabled(!coordinator.store.hasContent)
            } else {
                Spacer()
                if !coordinator.statusMessage.isEmpty { liveStatus }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .alert("Operation Failed", isPresented: showsSaveError) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .sheet(isPresented: $showingPreparation) {
            if let record = coordinator.workspaceRecord, let history = coordinator.history {
                VStack(spacing: 0) {
                    HStack { Spacer(); Button("Done") { showingPreparation = false } }.padding(12)
                    MeetingPreparationView(record: record, history: history,
                                editor: coordinator.vocabularyEditor(for: record, settings: aiSettings))
                        .id(record.id)
                }.frame(width: 620, height: 640)
                    .modifier(SettingsSheet())
            }
        }
        .onChange(of: coordinator.selectedRecordID) { _, _ in showingPreparation = false }
        .onChange(of: selectedRecord?.id) { _, _ in cancelRefinement() }
        .onDisappear { cancelRefinement() }
    }

    private var showsSaveError: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            if coordinator.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(CaptionsView.muted)
            } else {
                RecordingDot()
            }
            MeetingTimer(coordinator: coordinator)
            if coordinator.isPaused {
                Text("Paused")
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.muted)
            }
        }
    }

    private var liveStatus: some View {
        HStack(spacing: 8) {
            if coordinator.isRunning {
                recordingStatus
            }
            if coordinator.isRunning && !coordinator.statusMessage.isEmpty {
                Circle()
                    .fill(CaptionsView.borderSoft)
                    .frame(width: 3, height: 3)
            }
            if !coordinator.statusMessage.isEmpty {
                Text(coordinator.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.muted)
                    .lineLimit(1)
                    .help(coordinator.statusMessage)
            }
        }
    }

    private func refineButton(_ record: MeetingRecord) -> some View {
        let configured = aiSettings.isConfigured
        let state = coordinator.refiner?.state ?? .idle
        let busy: Bool = if case .refining = state { true } else { false }
        let failed: Bool = if case .error = state { true } else { false }
        let label: String = switch state {
        case .refining(let done, let total): "Refining \(done)/\(total)"
        case .error: "Refinement Failed — Retry"
        case .idle:
            if !configured { "Configure AI Services" }
            else if record.hasRefinement { "Refine Again" }
            else { record.languagePair.needsTranslation ? "Refine Translation" : "Refine Transcript" }
        }

        return Button {
            if configured {
                runRefinement(record)
            } else {
                settingsNavigation.openAISettings()
            }
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: failed ? "exclamationmark.arrow.circlepath" : "wand.and.stars")
                }
            }
            .frame(width: 28, height: 28)
            .foregroundStyle(failed ? CaptionsView.danger : CaptionsView.accent)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .disabled(busy)
        .padding(.trailing, 6)
    }

    private func runRefinement(_ record: MeetingRecord) {
        guard let refiner = coordinator.refiner else { return }
        cancelRefinement()
        let lines = record.lines
        let languagePair = record.languagePair
        let token = UUID()
        refinementToken = token
        if record.needsAITitle, let titleGenerator = coordinator.titleGenerator {
            titleTask = Task { @MainActor in
                do {
                    guard let title = try await titleGenerator.generateIfNeeded(for: record) else { return }
                    guard !Task.isCancelled,
                          refinementToken == token,
                          selectedRecord?.id == record.id,
                          record.needsAITitle else { return }
                    record.aiTitle = title
                    do {
                        try modelContext.save()
                    } catch {
                        modelContext.rollback()
                        throw error
                    }
                } catch is CancellationError {
                    return
                } catch let error as LLMError {
                    guard refinementToken == token, record.needsAITitle else { return }
                    saveError = "Title generation failed. Transcript refinement is unaffected.\n\(error.errorDescription ?? "Unknown error")"
                } catch {
                    guard refinementToken == token, record.needsAITitle else { return }
                    saveError = "Title generation failed. Transcript refinement is unaffected.\n\(error.localizedDescription)"
                }
            }
        }
        refinementTask = Task { @MainActor in
            do {
                let outcome = try await refiner.refine(
                    lines: lines,
                    languagePair: languagePair,
                    priorGlossaryJSON: record.glossaryJSON
                )
                guard !Task.isCancelled,
                      refinementToken == token,
                      selectedRecord?.id == record.id else { return }
                for line in lines {
                    guard let refined = outcome.byIndex[line.orderIndex] else { continue }
                    let source = refined.source.trimmed
                    if !source.isEmpty {
                        line.refinedSource = source
                        if !languagePair.needsTranslation { line.refinedTarget = source }
                    }
                    if let target = refined.target?.trimmed, !target.isEmpty {
                        line.refinedTarget = target
                    }
                }
                record.glossaryJSON = outcome.glossaryJSON
                record.refinedAt = Date()
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    throw error
                }
                showRefined = true
            } catch is CancellationError {
                return
            } catch let error as LLMError {
                guard refinementToken == token else { return }
                saveError = error.errorDescription
            } catch {
                guard refinementToken == token else { return }
                saveError = error.localizedDescription
            }
        }
    }

    private func cancelRefinement() {
        refinementTask?.cancel()
        refinementTask = nil
        titleTask?.cancel()
        titleTask = nil
        refinementToken = UUID()
        coordinator.refiner?.cancel()
    }

    private func iconButton(_ systemName: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15))
                .foregroundStyle(CaptionsView.muted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MeetingControlDock: View {
    let coordinator: CaptureCoordinator

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                languages
                divider
                captureControls
            }
            .fixedSize()
            VStack(spacing: 6) {
                languages
                captureControls
            }
            .fixedSize()
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 12)
        .disabled(coordinator.isTransitioning)
        .onChange(of: coordinator.languagePair) { _, _ in coordinator.saveDraftLanguages() }
    }

    private var languages: some View {
        LanguagePicker(coordinator: coordinator)
            .disabled(coordinator.isRunning)
    }

    private var captureControls: some View {
        HStack(spacing: 6) {
            Button {
                Task { await coordinator.setCaptionMyMic(!coordinator.captionMyMic) }
            } label: {
                Image(systemName: coordinator.captionMyMic ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(coordinator.captionMyMic ? CaptionsView.accent : CaptionsView.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            divider

            if coordinator.isRunning {
                Button {
                    Task {
                        if coordinator.isPaused { await coordinator.resume() }
                        else { await coordinator.pause() }
                    }
                } label: {
                    Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(CaptionsView.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!coordinator.sessionState.acceptsCaptureControls)

                primaryButton(icon: "stop.fill", label: "End", color: CaptionsView.fg) {
                    Task { await coordinator.stop() }
                }
            } else {
                primaryButton(icon: "play.fill", label: "Start", color: CaptionsView.accent) {
                    Task { await coordinator.startGlobal() }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(CaptionsView.borderSoft)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }

    private func primaryButton(icon: String, label: String, color: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }
}

private struct LanguagePicker: View {
    let coordinator: CaptureCoordinator

    var body: some View {
        HStack(spacing: 5) {
            languageMenu(
                selection: coordinator.sourceLanguage,
                accessibilityLabel: "Source Language"
            ) { coordinator.sourceLanguage = $0 }

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CaptionsView.meta)

            languageMenu(
                selection: coordinator.targetLanguage,
                accessibilityLabel: "Target Language"
            ) { coordinator.targetLanguage = $0 }
        }
        .fixedSize()
    }

    private func languageMenu(
        selection: MeetingLanguage,
        accessibilityLabel: String,
        onSelect: @escaping (MeetingLanguage) -> Void
    ) -> some View {
        Menu {
            ForEach(MeetingLanguage.allCases) { language in
                Button { onSelect(language) } label: {
                    HStack {
                        Text(language.label)
                        if selection == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CaptionsView.fg)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CaptionsView.meta)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(accessibilityLabel): \(selection.label)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selection.label)
    }
}

private struct RecordingDot: View {
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(CaptionsView.danger)
            .frame(width: 6, height: 6)
            .opacity(isDimmed ? 0.4 : 1)
            .animation(.easeInOut(duration: 1).repeatForever(), value: isDimmed)
            .onAppear { isDimmed = true }
    }
}

private struct MeetingTimer: View {
    let coordinator: CaptureCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = max(0, Int(coordinator.elapsedSeconds))
            Text(String(format: "%02d:%02d:%02d", seconds / 3_600,
                        (seconds % 3_600) / 60, seconds % 60))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(CaptionsView.muted)
        }
    }
}
