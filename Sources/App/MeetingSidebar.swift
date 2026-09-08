import SwiftData
import SwiftUI

struct MeetingSidebar: View {
    let coordinator: CaptureCoordinator
    @Binding var selectedRecord: MeetingRecord?
    @Query(sort: \MeetingRecord.createdAt, order: .reverse) private var records: [MeetingRecord]
    @State private var meetingToDelete: MeetingRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 48)
            Text("Meetings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CaptionsView.muted)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(records) { record in recordRow(record) }
                    }
                    .padding(.horizontal, 12)
                }
            }
            newMeetingButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CaptionsView.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CaptionsView.borderSoft).frame(width: 1)
        }
        .alert("Delete meeting?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        ), presenting: meetingToDelete) { record in
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Delete", role: .destructive) {
                coordinator.delete(record)
            }
        } message: { record in
            Text("\u{201c}\(record.displayTitle)\u{201d} and its transcript, documents, vocabulary, and insights will be permanently deleted. This cannot be undone.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22))
                .foregroundStyle(CaptionsView.meta.opacity(0.5))
            Text("No meetings yet")
                .font(.system(size: 12))
                .foregroundStyle(CaptionsView.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var newMeetingButton: some View {
        let activelyRecording = coordinator.sessionState == .recording
        return VStack(spacing: 0) {
            Rectangle().fill(CaptionsView.borderSoft).frame(height: 1)
            Button {
                Task {
                    await coordinator.startNewMeeting()
                }
            } label: {
                Label("New Meeting", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        activelyRecording ? CaptionsView.muted.opacity(0.5) : CaptionsView.accent
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CaptionsView.accent.opacity(activelyRecording ? 0.03 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(activelyRecording || coordinator.isTransitioning)
            .padding(12)
        }
    }

    private func recordRow(_ record: MeetingRecord) -> some View {
        let isCurrent = record.id == coordinator.activeRecordID
        let isUnfinished = record.meetingStatus != .ended
        let isRecording = isCurrent && coordinator.sessionState == .recording
        let isSelected = isCurrent ? selectedRecord == nil : selectedRecord?.id == record.id
        let subtitle: String
        let detail: String?
        if isUnfinished {
            subtitle = record.meetingStatus == .draft ? "Preparation" : isRecording ? "Recording…" : "Paused"
            detail = nil
        } else if record.hasTitle {
            subtitle = record.displayDate
            detail = record.metaText
        } else {
            subtitle = record.metaText
            detail = nil
        }

        return Button {
            if isCurrent {
                selectedRecord = nil
            } else if isUnfinished {
                Task {
                    await coordinator.loadSession(record)
                }
            } else {
                Task { await coordinator.openHistory(record) }
            }
        } label: {
            sidebarRow(
                title: record.displayTitle,
                subtitle: subtitle,
                detail: detail,
                highlighted: isUnfinished,
                selected: isSelected,
                showsRecordingDot: isRecording,
                activity: coordinator.backgroundActivity(for: record.id)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isCurrent || !coordinator.isRunning {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    meetingToDelete = record
                }
            }
        }
    }

    private func sidebarRow(title: String, subtitle: String, detail: String? = nil, highlighted: Bool,
                            selected: Bool, showsRecordingDot: Bool = false, activity: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? CaptionsView.accent : CaptionsView.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let activity {
                    ProgressView().controlSize(.mini)
                        .help(activity)
                        .accessibilityLabel(activity)
                }
            }
            HStack(spacing: 5) {
                if showsRecordingDot {
                    Circle().fill(CaptionsView.danger).frame(width: 5, height: 5)
                }
                Text(subtitle)
            }
            .font(.system(size: 11))
            .foregroundStyle(highlighted ? CaptionsView.accent.opacity(0.85) : CaptionsView.meta)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(CaptionsView.meta)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? CaptionsView.accent.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }
}
