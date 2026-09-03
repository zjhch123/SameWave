import SwiftData
import SwiftUI

struct MeetingStage: View {
    let coordinator: CaptureCoordinator
    @Binding var sidebarOpen: Bool
    @Binding var selectedRecord: MeetingRecord?
    @State private var showRefined = true

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
            } else {
                CaptionsView(
                    store: coordinator.store,
                    isListening: coordinator.isRunning,
                    statusMessage: coordinator.statusMessage,
                    hideSourceEcho: !coordinator.meetingLanguage.needsTranslation
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MeetingControlDock(
                        coordinator: coordinator,
                        selectedRecord: $selectedRecord
                    )
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
    @Environment(\.openSettings) private var openSettings
    @State private var saveError: String?
    @State private var refinementTask: Task<Void, Never>?
    @State private var refinementToken = UUID()

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarOpen { Color.clear.frame(width: 64) }
            iconButton("sidebar.left", help: "切换边栏") { sidebarOpen.toggle() }

            if let record = selectedRecord {
                HStack(spacing: 10) {
                    Text(record.displayDate)
                        .font(.system(size: 15, weight: .semibold))
                    Text(record.metaText)
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                .padding(.leading, 10)
                Spacer()

                if record.hasRefinement {
                    Picker("", selection: $showRefined) {
                        Text("优化").tag(true)
                        Text("原始").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.trailing, 4)
                }
                refineButton(record)
                iconButton("square.and.arrow.up", help: "导出这次会议") {
                    TranscriptExporter.exportRecord(record)
                }
            } else {
                Spacer()
                if coordinator.isRunning || !coordinator.statusMessage.isEmpty {
                    liveStatus
                }
                Spacer()
                iconButton("square.and.arrow.up", help: "导出全文") {
                    TranscriptExporter.exportWithPanel(
                        store: coordinator.store,
                        showsSourceEcho: coordinator.meetingLanguage.needsTranslation
                    )
                }
                .disabled(!coordinator.store.hasContent)
            }
        }
        .padding(.horizontal, 16)
        .alert("操作失败", isPresented: showsSaveError) {
            Button("好") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
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
                Text("已暂停")
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
        let configured = coordinator.insights?.isConfigured == true
        let state = coordinator.refiner?.state ?? .idle
        let busy: Bool = if case .refining = state { true } else { false }
        let failed: Bool = if case .error = state { true } else { false }
        let label: String = switch state {
        case .refining(let done, let total): "优化中 \(done)/\(total)"
        case .error: "优化失败，重试"
        case .idle: configured ? (record.hasRefinement ? "重新优化" : "优化译文") : "去设置"
        }

        return Button {
            if configured { runRefinement(record) } else { openSettings() }
        } label: {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: failed ? "exclamationmark.arrow.circlepath" : "wand.and.stars")
                }
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(failed ? CaptionsView.danger : CaptionsView.accent)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.trailing, 6)
    }

    private func runRefinement(_ record: MeetingRecord) {
        guard let refiner = coordinator.refiner else { return }
        cancelRefinement()
        let lines = record.lines
        let language = record.meetingLanguage
        let token = UUID()
        refinementToken = token
        refinementTask = Task { @MainActor in
            do {
                let outcome = try await refiner.refine(
                    lines: lines,
                    language: language,
                    priorGlossaryJSON: record.glossaryJSON
                )
                guard !Task.isCancelled,
                      refinementToken == token,
                      selectedRecord?.id == record.id else { return }
                for line in lines {
                    guard let refined = outcome.byIndex[line.orderIndex] else { continue }
                    if let source = refined.source?.trimmed, !source.isEmpty {
                        line.refinedSource = source
                        if !language.needsTranslation { line.refinedTarget = source }
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
    @Binding var selectedRecord: MeetingRecord?

    var body: some View {
        HStack(spacing: 6) {
            LanguagePicker(coordinator: coordinator)
                .disabled(coordinator.isRunning)
            divider
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

                primaryButton(icon: "stop.fill", label: "结束", color: CaptionsView.fg) {
                    Task { selectedRecord = await coordinator.stop() }
                }
            } else {
                primaryButton(icon: "play.fill", label: "开始", color: CaptionsView.accent) {
                    Task { await coordinator.startGlobal() }
                }
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .disabled(coordinator.isTransitioning)
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
        HStack(spacing: 2) {
            ForEach(MeetingLanguage.allCases) { language in
                let isSelected = coordinator.meetingLanguage == language
                Button { coordinator.meetingLanguage = language } label: {
                    Text(language.shortLabel)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? CaptionsView.fg : CaptionsView.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(isSelected ? CaptionsView.bg : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.04)))
        .fixedSize()
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
