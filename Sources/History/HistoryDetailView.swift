import SwiftData
import SwiftUI

/// Read-only view of a saved meeting from history — the same centered transcript
/// style as the live view, each line tagged with its speaker, spoken time, target-language
/// translation, and source text. The meeting's title/meta and its export action live
/// in the stage's top bar (StageHeader); its AI insight lives in the right Inspector
/// (the single home for insights) — this view is PURE transcript, no duplicate panel.
struct HistoryDetailView: View {
    let record: MeetingRecord
    /// Whether to show the LLM-refined text (page-wide Original/Refined toggle, owned by the
    /// stage). Falls back to originals per-line when a line has no refined variant.
    var showRefined: Bool = false

    private var lines: [TranscriptLine] {
        record.lines.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(lines) { line in
                    row(line)
                }
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(CaptionsView.bg)
    }

    @ViewBuilder
    private func row(_ line: TranscriptLine) -> some View {
        let mine = line.isMine
        let target = line.displayTarget(refined: showRefined).trimmed
        let source = line.displaySource(refined: showRefined)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(mine ? "You" : "Speaker")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(mine ? CaptionsView.accent : CaptionsView.meta)
                Text(line.timeText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CaptionsView.meta.opacity(0.7))
            }
            Text(target.isEmpty ? source : target)
                .font(.system(size: 25, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(CaptionsView.fg)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Source echo: only for a TRANSLATED meeting (record.showsSourceEcho), and
            // only when the primary line is the translation (target non-empty) and the
            // source genuinely differs. A same-language meeting stores source == target (the
            // recognized text IS the caption), so pair-gating suppresses the near-duplicate
            // that pure equality misses when the two were snapshotted a beat apart.
            if record.showsSourceEcho && !target.isEmpty && !source.isEmpty && source != target {
                Text(source)
                    .font(.system(size: 14))
                    .foregroundStyle(CaptionsView.muted)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
