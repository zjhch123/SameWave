import SwiftData
import SwiftUI

/// The integrated main window — a macOS-native three-column layout (after the
/// reference index.html): a collapsible "会议记录" sidebar, a white live-transcript
/// stage with a floating glass control dock, and an "智能洞察" inspector.
struct MainView: View {
    let coordinator: CaptureCoordinator

    @State private var sidebarOpen = true
    /// A selected past meeting to view, or nil for the live transcript.
    @State private var selectedRecord: MeetingRecord?
    /// Width of the right 智能洞察 inspector — user-resizable via the drag handle on its
    /// left edge, persisted so it's remembered across launches. Clamped to a sane range.
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 280
    private static let inspectorMin: Double = 240
    private static let inspectorMax: Double = 620

    var body: some View {
        HStack(spacing: 0) {
            if sidebarOpen {
                Sidebar(coordinator: coordinator, selectedRecord: $selectedRecord)
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            MainStage(coordinator: coordinator, sidebarOpen: $sidebarOpen,
                      selectedRecord: $selectedRecord)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Draggable divider — resizes the inspector. Dragging left widens it; the
            // width is computed from drag-start width + global translation (stable, no
            // jitter) and clamped to [min, max].
            InspectorResizeHandle(width: $inspectorWidth,
                                  minWidth: Self.inspectorMin,
                                  maxWidth: Self.inspectorMax)

            Inspector(coordinator: coordinator, selectedRecord: $selectedRecord)
                .frame(width: inspectorWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CaptionsView.bg)
        .ignoresSafeArea(.container, edges: .top)
        // The TranslationPump hosts the long-lived Translation session; it MUST
        // stay on a persistent view or captions never get translated.
        .modifier(TranslationPump(bridge: coordinator.translation,
                                  sourceLanguage: coordinator.meetingLanguage.translationSource ?? "en"))
        // Starting a new recording jumps back to the live view.
        .onChange(of: coordinator.store.isRunning) { _, running in
            if running { selectedRecord = nil }
        }
        .animation(.easeOut(duration: 0.22), value: sidebarOpen)
    }
}

// MARK: - Left sidebar (会议记录 — real history)

private struct Sidebar: View {
    let coordinator: CaptureCoordinator
    @Binding var selectedRecord: MeetingRecord?

    // Newest first. SwiftData drives this live. ALL sessions are listed here — an
    // in-progress / paused / recovered meeting shows up too (it's on disk from the
    // start, for crash recovery), tagged with its live status; only truly-empty ones
    // are absent (they were never persisted). One unified, time-ordered list.
    @Query(sort: \MeetingRecord.startedAt, order: .reverse) private var records: [MeetingRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 48pt header band reserved for the traffic lights (they float here);
            // the "会议记录" title sits BELOW it, in the sidebar content area.
            Color.clear.frame(height: 48)

            Text("会议记录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CaptionsView.muted)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // The "新会议" placeholder appears at the top whenever the stage is a blank
            // live view (idle, nothing mounted): a selected reminder of the current
            // state. The moment 开始 is pressed the real record takes over the top slot
            // (time title + 录制中… status), so the placeholder is only ever a preview.
            let showPlaceholder = selectedRecord == nil && !coordinator.store.isRunning

            if records.isEmpty && !showPlaceholder {
                // Vertically-centered empty state, mirroring the 智能洞察
                // placeholder: Spacers above and below, not a bottom-pinned block.
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22))
                        .foregroundStyle(CaptionsView.meta.opacity(0.5))
                    Text("还没有历史记录")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.muted)
                    Text("结束一次会议后会自动保存")
                        .font(.system(size: 11))
                        .foregroundStyle(CaptionsView.muted.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if showPlaceholder { newSessionPlaceholderRow }
                        ForEach(records) { rec in
                            sessionRow(rec)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            // Pinned to the bottom: start a fresh meeting.
            newMeetingButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CaptionsView.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CaptionsView.borderSoft).frame(width: 1)
        }
    }

    /// Bottom-pinned "new meeting" action. Suspends whatever session is mounted (kept
    /// on disk as a resumable paused meeting — lossless, no archive, no confirm) and
    /// clears the stage to a blank live view. Disabled only while ACTIVELY recording
    /// (running & not paused) — pause or end it first; paused / ended / idle are fine.
    private var newMeetingButton: some View {
        let recording = coordinator.store.isRunning && !coordinator.isPaused
        return VStack(spacing: 0) {
            Rectangle().fill(CaptionsView.borderSoft).frame(height: 1)
            Button {
                coordinator.startNewMeeting()
                selectedRecord = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                    Text("开启新会议")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(recording ? CaptionsView.muted.opacity(0.5) : CaptionsView.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill((recording ? CaptionsView.muted : CaptionsView.accent).opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(recording)
            .help(recording ? "会议进行中，请先暂停或结束" : "开启新会议")
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    /// A virtual, non-persisted "新会议" row pinned to the top of the list while the
    /// stage is a blank live view (idle). It's shown SELECTED — a reminder that the
    /// current view is a fresh, not-yet-started session. Tapping it just ensures the
    /// live view is shown. Once 开始 is pressed the real record appears at the top
    /// (time title + status) and this placeholder disappears, so the title appears to
    /// morph from "新会议" into the timestamp.
    private var newSessionPlaceholderRow: some View {
        Button {
            selectedRecord = nil   // stay on the (blank) live view
        } label: {
            Self.sidebarRow(title: "新会议", subtitle: "尚未开始",
                            accentSubtitle: true, selected: true)
        }
        .buttonStyle(.plain)
    }

    /// The shared sidebar-row chrome: a time/name title over an optional subtitle,
    /// with the selected-state highlight. Used by both the "新会议" placeholder and
    /// every session row so the look is defined once.
    /// - Parameters:
    ///   - accentSubtitle: subtitle in accent blue (a live/paused status) vs muted meta.
    ///   - dot: an optional leading dot color before the subtitle (the recording dot).
    @ViewBuilder
    static func sidebarRow(title: String, subtitle: String?, accentSubtitle: Bool,
                           selected: Bool, dot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? CaptionsView.accent : CaptionsView.fg)
                .lineLimit(1)
            if let subtitle {
                HStack(spacing: 5) {
                    if let dot { Circle().fill(dot).frame(width: 5, height: 5) }
                    Text(subtitle)
                }
                .font(.system(size: 11))
                .foregroundStyle(accentSubtitle ? CaptionsView.accent.opacity(0.85) : CaptionsView.meta)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? CaptionsView.accent.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())   // whole row hittable, not just the text
    }

    /// One unified session row. Titled by time. An unfinished session (paused, or the
    /// live one) shows a status subtitle: the currently-mounted one taps into the LIVE
    /// view; any OTHER paused meeting taps to LOAD it (mount & continue). Ended meetings
    /// show "N 段 · 时长" and tap into the read-only detail view.
    private func sessionRow(_ rec: MeetingRecord) -> some View {
        let isCurrent = rec.id == coordinator.activeRecordID && coordinator.store.isRunning
        let isUnfinished = rec.status != "ended"
        let isRecording = isCurrent && !coordinator.isPaused
        let selected = isCurrent ? (selectedRecord == nil) : (selectedRecord?.id == rec.id)
        // Live status subtitle for unfinished sessions; "N 段 · 时长" for ended ones.
        let subtitle = isUnfinished ? (isRecording ? "录制中…" : "已暂停") : rec.metaText
        return Button {
            if isCurrent {
                selectedRecord = nil            // mounted session → live view
            } else if isUnfinished {
                coordinator.loadSession(rec)    // another paused meeting → mount & continue
                selectedRecord = nil
            } else {
                selectedRecord = rec            // ended meeting → read-only detail
            }
        } label: {
            Self.sidebarRow(title: rec.displayDate, subtitle: subtitle,
                            accentSubtitle: isUnfinished, selected: selected,
                            dot: isRecording ? CaptionsView.danger : nil)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Don't offer to delete the session that's currently mounted/recording.
            if !isCurrent {
                Button(role: .destructive) {
                    if selected { selectedRecord = nil }
                    coordinator.history?.delete(rec)
                } label: { Label("删除", systemImage: "trash") }
            }
        }
    }
}

// MARK: - Center stage (transcript + header + dock)

private struct MainStage: View {
    let coordinator: CaptureCoordinator
    @Binding var sidebarOpen: Bool
    @Binding var selectedRecord: MeetingRecord?
    /// Page-wide 原始/优化 toggle for the selected history meeting. Reset per meeting via
    /// the `.id(rec.id)` below, and defaulted to "优化" when that meeting has a refinement.
    @State private var showRefined = true

    var body: some View {
        VStack(spacing: 0) {
            StageHeader(coordinator: coordinator, sidebarOpen: $sidebarOpen,
                        selectedRecord: $selectedRecord, showRefined: $showRefined)
                .frame(height: 48)

            if let rec = selectedRecord {
                // Viewing a saved meeting from history (title/export/refine live in header).
                HistoryDetailView(record: rec, showRefined: showRefined && rec.hasRefinement)
                    .id(rec.id)   // distinct identity per meeting → no state/scroll bleed
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CaptionsView(store: coordinator.store,
                             statusMessage: coordinator.statusMessage,
                             hideSourceEcho: !coordinator.meetingLanguage.needsTranslation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The dock lives in a bottom safe-area INSET, not an overlay: this
                    // carves its band out of the scroll region, so transcript text stops
                    // above the dock and never scrolls behind its translucent glass.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        FloatingDock(coordinator: coordinator, selectedRecord: $selectedRecord)
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

    private var isRunning: Bool { coordinator.store.isRunning }

    var body: some View {
        HStack(spacing: 0) {
            // Leading: sidebar toggle. Reserve room for traffic lights when the
            // sidebar is closed (they'd otherwise overlap this button).
            HStack(spacing: 12) {
                if !sidebarOpen { Color.clear.frame(width: 64) }
                iconButton("sidebar.left", help: "切换边栏") {
                    sidebarOpen.toggle()
                }
            }

            if let rec = selectedRecord {
                // Viewing history: the meeting's title + meta sit in the header.
                HStack(spacing: 10) {
                    Text(rec.displayDate)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CaptionsView.fg)
                    Text(rec.metaText)
                        .font(.system(size: 12))
                        .foregroundStyle(CaptionsView.meta)
                }
                .padding(.leading, 10)
                Spacer()

                // 原始/优化 page-wide toggle — only once this meeting has a refinement.
                if rec.hasRefinement {
                    Picker("", selection: $showRefined) {
                        Text("优化").tag(true)
                        Text("原始").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.trailing, 4)
                }

                // Refine action (generate / regenerate the refined transcript).
                refineButton(rec)

                // Trailing: export THIS record (uses the refined version when present).
                iconButton("square.and.arrow.up", help: "导出这次会议") {
                    TranscriptExporter.exportRecord(rec)
                }
            } else {
                Spacer()

                // Center: recording indicator + timer (live view only).
                if isRunning {
                    HStack(spacing: 8) {
                        if coordinator.isPaused {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(CaptionsView.muted)
                        } else {
                            RecordingDot()
                        }
                        TimerText(coordinator: coordinator)
                        if coordinator.isPaused {
                            Text("已暂停")
                                .font(.system(size: 11))
                                .foregroundStyle(CaptionsView.muted)
                        }
                    }
                }

                Spacer()

                // Trailing: export the live transcript.
                iconButton("square.and.arrow.up", help: "导出全文") {
                    TranscriptExporter.exportWithPanel(
                        store: coordinator.store,
                        showsSourceEcho: coordinator.meetingLanguage.needsTranslation)
                }
                .disabled(!coordinator.store.hasContent)
            }
        }
        .padding(.horizontal, 16)
    }

    /// The refine action for a history meeting: runs the LLM second pass (batched), writes
    /// the refined text back onto each line + stamps `refinedAt`/`glossaryJSON`. Shows batch
    /// progress; if unconfigured, routes to Settings instead.
    @ViewBuilder
    private func refineButton(_ rec: MeetingRecord) -> some View {
        let configured = coordinator.insights?.isConfigured == true
        let refineState = coordinator.insights?.refineState ?? .idle
        let busy: Bool = { if case .refining = refineState { return true }; return false }()
        let failed: Bool = { if case .error = refineState { return true }; return false }()
        let label: String = {
            if !configured { return "去设置" }
            if case .refining(let d, let t) = refineState { return "优化中 \(d)/\(t)" }
            if case .error = refineState { return "优化失败，重试" }
            return rec.hasRefinement ? "重新优化" : "优化译文"
        }()
        let helpText: String = {
            if case .error(let e) = refineState { return e.errorDescription ?? "优化失败" }
            return "用 AI 优化译文并清理原文（保留原始版可切换）"
        }()
        Button {
            if configured { runRefine(rec) } else { openSettings() }
        } label: {
            HStack(spacing: 5) {
                if busy { ProgressView().controlSize(.small) }
                else { Image(systemName: failed ? "exclamationmark.arrow.circlepath"
                                        : rec.hasRefinement ? "arrow.clockwise" : "wand.and.stars")
                        .font(.system(size: 12)) }
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(failed ? CaptionsView.danger : CaptionsView.accent)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(helpText)
        .padding(.trailing, 6)
    }

    private func runRefine(_ rec: MeetingRecord) {
        guard let engine = coordinator.insights else { return }
        let lines = rec.lines
        let language = rec.meetingLanguage
        let priorGlossary = rec.glossaryJSON
        Task { @MainActor in
            do {
                let outcome = try await engine.refineOnce(lines: lines, language: language,
                                                          priorGlossaryJSON: priorGlossary)
                // Write refined text back per line, matched by orderIndex; unmatched lines
                // keep their originals (refined* stays nil). For a Chinese meeting the model
                // returns SOURCE only (target == source), so mirror the cleaned source into
                // refinedTarget too — otherwise the primary line (which shows target) wouldn't
                // update.
                let mirrors = !language.needsTranslation
                for line in lines {
                    if let r = outcome.byIndex[line.orderIndex] {
                        if let s = r.source?.trimmed, !s.isEmpty {
                            line.refinedSource = s
                            if mirrors { line.refinedTarget = s }
                        }
                        if let t = r.target?.trimmed, !t.isEmpty { line.refinedTarget = t }
                    }
                }
                rec.glossaryJSON = outcome.glossaryJSON
                rec.refinedAt = Date()
                try? modelContext.save()
                showRefined = true   // reveal the refined version once it lands
            } catch {
                // refineState already carries the error for the button; nothing to do.
            }
        }
    }

    private func iconButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15))
                .foregroundStyle(CaptionsView.muted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A pulsing red recording dot.
private struct RecordingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(CaptionsView.danger)
            .frame(width: 6, height: 6)
            .overlay(Circle().stroke(CaptionsView.danger.opacity(0.25), lineWidth: 3))
            .opacity(on ? 0.4 : 1)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// HH:MM:SS elapsed meeting time (frozen while paused).
private struct TimerText: View {
    let coordinator: CaptureCoordinator
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(format(coordinator.elapsedSeconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(CaptionsView.muted)
        }
    }
    private func format(_ sec: TimeInterval) -> String {
        let s = max(0, Int(sec))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

// MARK: - Floating glass control dock

private struct FloatingDock: View {
    let coordinator: CaptureCoordinator
    @Binding var selectedRecord: MeetingRecord?
    private var isRunning: Bool { coordinator.store.isRunning }

    var body: some View {
        HStack(spacing: 6) {
            LangSegmented(coordinator: coordinator).disabled(isRunning)

            dockDivider

            // Mic toggle (hot-swappable mid-session).
            Button {
                coordinator.setCaptionMyMic(!coordinator.captionMyMic)
            } label: {
                Image(systemName: coordinator.captionMyMic ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(coordinator.captionMyMic ? CaptionsView.accent : CaptionsView.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help(coordinator.captionMyMic ? "正在字幕我的麦克风 · 点击关闭" : "未字幕我的麦克风 · 点击开启")

            dockDivider

            // Primary start / stop.
            if isRunning {
                // Pause / resume.
                Button {
                    if coordinator.isPaused { coordinator.resume() } else { coordinator.pause() }
                } label: {
                    Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(CaptionsView.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(coordinator.isPaused ? "继续录制" : "暂停")

                primaryPill(icon: "stop.fill", label: "结束", fill: CaptionsView.fg) {
                    // End the meeting and keep it SELECTED in the sidebar, showing its
                    // read-only detail (rather than dropping to a blank live view).
                    selectedRecord = coordinator.stop()
                }
            } else {
                primaryPill(icon: "play.fill", label: "开始", fill: CaptionsView.accent) {
                    coordinator.startGlobal()
                }
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    /// The white-on-color capsule for the dock's primary action (开始 / 结束).
    private func primaryPill(icon: String, label: String, fill: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }

    private var dockDivider: some View {
        Rectangle().fill(CaptionsView.borderSoft)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }
}

/// A gray-track segmented control with a white "pill" for the selected segment.
private struct LangSegmented: View {
    let coordinator: CaptureCoordinator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CaptureCoordinator.MeetingLanguage.allCases) { lang in
                let selected = coordinator.meetingLanguage == lang
                Button {
                    coordinator.meetingLanguage = lang
                } label: {
                    Text(lang.shortLabel)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? CaptionsView.fg : CaptionsView.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(selected ? CaptionsView.bg : .clear)
                                .shadow(color: selected ? .black.opacity(0.08) : .clear,
                                        radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.04)))
        .fixedSize()
    }
}

// MARK: - Right inspector (智能洞察 — the single home for AI insights)

/// A thin visible divider with a wide invisible hit area that resizes the inspector.
/// Resizing is computed from the width captured at drag-start plus the TOTAL translation
/// in GLOBAL coordinates — never an incremental delta. That matters: the handle itself
/// shifts as the inspector grows, so an incremental/local-space delta feeds back on
/// itself and jitters. Start-width + global-translation is stable.
private struct InspectorResizeHandle: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    /// Inspector width when the current drag began; nil while not dragging.
    @State private var startWidth: Double? = nil

    var body: some View {
        Rectangle()
            .fill(CaptionsView.borderSoft)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            // Widen the interactive zone without widening the visible line.
            .overlay(Color.clear.frame(width: 10).contentShape(Rectangle()))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = base }
                        // Dragging left (negative x) widens the inspector.
                        width = min(maxWidth, max(minWidth, base - value.translation.width))
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

/// The ONE place insights render — so the center stage stays pure transcript and there's
/// no duplicate "智能洞察" panel. It follows whatever the center shows:
/// • Live view (no `selectedRecord`) → the live engine's rolling insight.
/// • A saved meeting selected → that record's cached insight, with a 生成/重新生成 action
///   that runs a one-shot pass and caches it back onto the record.
private struct Inspector: View {
    let coordinator: CaptureCoordinator
    @Binding var selectedRecord: MeetingRecord?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext

    private var insights: InsightEngine? { coordinator.insights }
    private var configured: Bool { insights?.isConfigured ?? false }

    /// One-shot history generation state (only used in history mode).
    private enum GenState: Equatable { case idle, generating, failed(String) }
    @State private var genState: GenState = .idle
    /// The cached/just-generated insight for the selected history record.
    @State private var historyInsight: InsightResult?

    var body: some View {
        VStack(spacing: 0) {
            // Header (48pt). A spinner shows while EITHER the live engine or a history
            // pass is generating. The gear (settings) is always present.
            HStack(spacing: 8) {
                Text("智能洞察")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CaptionsView.fg)
                if isGenerating { ProgressView().controlSize(.small) }
                Spacer()
                // In history mode, a generate / regenerate action lives in the header.
                if selectedRecord != nil { historyGenerateButton }
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(CaptionsView.muted)
                }
                .buttonStyle(.plain)
                .help("智能洞察设置")
            }
            .frame(height: 48)
            .padding(.horizontal, 16)

            Rectangle().fill(CaptionsView.borderSoft).frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CaptionsView.bg)
        // Left border is drawn by the adjacent InspectorResizeHandle (so it doubles as
        // the drag target) — no overlay here.
        // Load the selected record's cached insight when it changes (or clear for live).
        .onChange(of: selectedRecord?.id) { _, _ in syncHistory() }
        .onAppear { syncHistory() }
    }

    private var isGenerating: Bool {
        if genState == .generating { return true }
        if selectedRecord == nil, case .generating = insights?.state { return true }
        return false
    }

    // MARK: - Body content (live vs history)

    @ViewBuilder private var content: some View {
        if let record = selectedRecord {
            // History mode — that meeting's insight (cached or freshly generated).
            historyContent(record)
        } else {
            // Live mode — the rolling engine result.
            InsightCardsView(
                result: insights?.current ?? .empty,
                state: insights?.state ?? .idle,
                isConfigured: configured,
                onOpenSettings: { openSettings() },
                centersPlaceholder: true)
        }
    }

    @ViewBuilder private func historyContent(_ record: MeetingRecord) -> some View {
        if !configured {
            InsightCardsView(result: .empty, state: .idle, isConfigured: false,
                             onOpenSettings: { openSettings() }, centersPlaceholder: true)
        } else if let insight = historyInsight, !insight.isEmpty {
            ScrollView {
                InsightCardsView(result: insight, state: .done, isConfigured: true)
                    .padding(16)
            }
        } else if case .generating = genState {
            InsightCardsView(result: .empty, state: .generating, isConfigured: true,
                             centersPlaceholder: true)
        } else if case .failed(let msg) = genState {
            centeredHint(msg, color: CaptionsView.danger)
        } else {
            centeredHint("点击右上「生成洞察」，让 AI 为这次会议提炼话题、待办与决策。",
                         color: CaptionsView.muted)
        }
    }

    private func centeredHint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - History generation

    private var historyGenerateButton: some View {
        let hasResult = (historyInsight?.isEmpty == false)
        let busy = genState == .generating
        return Button {
            if configured { generateHistory() } else { openSettings() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasResult ? "arrow.clockwise" : "sparkles")
                    .font(.system(size: 12))
                Text(!configured ? "去设置" : hasResult ? "重新生成" : "生成洞察")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(CaptionsView.accent)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// Seed the shown history insight from the selected record's cache (or clear it).
    private func syncHistory() {
        historyInsight = selectedRecord?.insight
        genState = .idle
        coordinator.insights?.resetRefine()   // clear stale refine progress/error on switch
    }

    private func generateHistory() {
        guard let record = selectedRecord, let engine = coordinator.insights else { return }
        genState = .generating
        let transcript = InsightEngine.flatten(lines: record.lines)
        let language = record.meetingLanguage
        Task { @MainActor in
            do {
                let result = try await engine.generateOnce(transcript: transcript,
                                                            language: language)
                historyInsight = result
                genState = .idle
                record.insightJSON = result.encoded()   // cache for instant reopen + export
                try? modelContext.save()
            } catch let e as LLMError {
                genState = .failed(e.errorDescription ?? "生成失败")
            } catch {
                genState = .failed(error.localizedDescription)
            }
        }
    }
}
