import SwiftUI

/// Main control window: pick an audio source, start/stop captioning, manage the
/// overlay, and export a transcript.
struct ControlView: View {
    let coordinator: CaptureCoordinator
    let overlay: OverlayController
    @State private var clickThrough = false

    /// Auto-refresh the audio-source list while we're on the picker, so apps that
    /// just started playing show up without the user clicking 刷新. Fires every 2s;
    /// the handler no-ops while a session is running.
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            if coordinator.store.isRunning {
                runningControls
            } else {
                sourcePicker
            }

            Divider()

            overlayControls

            Spacer(minLength: 0)

            footer
        }
        .padding(20)
        .onAppear { coordinator.refreshProcesses() }
        .onReceive(refreshTimer) { _ in
            // Only while picking a source; pointless (and wasteful) mid-session.
            if !coordinator.store.isRunning { coordinator.refreshProcesses() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "captions.bubble.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("会议字幕").font(.headline)
                Text(coordinator.store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.store.isRunning {
                Circle().fill(.green).frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        Text("会议语言").font(.subheadline).bold()
        Picker("会议语言", selection: Binding(
            get: { coordinator.meetingLanguage },
            set: { coordinator.meetingLanguage = $0 })) {
            ForEach(CaptureCoordinator.MeetingLanguage.allCases) { lang in
                Text(lang.label).tag(lang)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text("选择要翻译的音频来源").font(.subheadline).bold()
        Menu {
            Button {
                coordinator.startGlobal()
            } label: {
                Label("全部系统音频", systemImage: "speaker.wave.3.fill")
            }
            if !coordinator.available.isEmpty {
                Divider()
                ForEach(coordinator.available) { proc in
                    Button {
                        coordinator.start(process: proc)
                    } label: {
                        // Playing apps get a badge so the user spots the live one.
                        Text(proc.isPlaying ? "🔊  \(proc.name)" : proc.name)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "waveform")
                Text("选择应用并开始…")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .menuStyle(.borderlessButton)
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))

        if coordinator.available.isEmpty {
            Text("暂无可捕获的应用。打开会议软件后列表会自动刷新。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var runningControls: some View {
        Button(role: .destructive) {
            coordinator.stop()
        } label: {
            Label("停止字幕", systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var overlayControls: some View {
        Text("悬浮字幕窗").font(.subheadline).bold()
        HStack {
            Button("显示") { overlay.show() }
            Button("隐藏") { overlay.hide() }
        }
        Toggle("鼠标点击穿透（可点到窗口下方）", isOn: $clickThrough)
            .onChange(of: clickThrough) { _, on in overlay.toggleClickThrough(on) }
            .font(.callout)
    }

    private var footer: some View {
        HStack {
            Button("导出纪要…") { exportTranscript() }
                .disabled(coordinator.store.lines.isEmpty && coordinator.store.block.isEmpty)
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    // MARK: - Export (wired in the transcript-export step)

    private func exportTranscript() {
        TranscriptExporter.exportWithPanel(store: coordinator.store)
    }
}
