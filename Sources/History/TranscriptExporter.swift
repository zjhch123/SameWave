import AppKit
import Foundation

/// Exports the captured captions as a Markdown transcript (target + source text).
@MainActor
enum TranscriptExporter {

    private static let header = "# Meeting Transcript\n\n"

    // MARK: - Markdown

    /// Build the Markdown from the live store's sections, in id (speech-onset) order.
    /// `showsSourceEcho` is true only when source and target languages differ;
    /// a same-language meeting's source equals its caption, so its echo is suppressed.
    static func markdown(store: CaptionStore, showsSourceEcho: Bool) -> String {
        let entries = store.sections
        var md = header
        md += "> Generated locally by SameWave · Sections: \(entries.count)\n\n---\n\n"
        for (i, sec) in entries.enumerated() {
            let target = sec.targetText.trimmed
            let who = sec.speaker == .mine ? "Me" : "Other party"
            if !target.isEmpty { md += "**\(i + 1). \(who):** \(target)\n\n" }
            appendSourceEcho(&md, source: sec.sourceText, target: target, enabled: showsSourceEcho)
        }
        return md
    }

    /// Markdown for a persisted meeting (with per-line spoken times). When the meeting has
    /// an LLM refinement, exports the refined text (falling back to originals per line) and
    /// notes it in the header — so a shared minute reflects the polished version.
    static func markdown(record: MeetingRecord) -> String {
        let lines = record.lines.sorted { $0.orderIndex < $1.orderIndex }
        let refined = record.hasRefinement
        var md = header
        let refinedNote = refined ? " · AI-refined" : ""
        md += "> Generated locally by SameWave · \(record.displayDate) · Sections: \(lines.count) · \(record.durationText)\(refinedNote)\n\n---\n\n"
        appendInsights(&md, record.insightSnapshots)
        for (i, line) in lines.enumerated() {
            let target = line.displayTarget(refined: refined).trimmed
            let source = line.displaySource(refined: refined)
            let who = line.isMine ? "Me" : "Other party"
            let head = target.isEmpty ? source : target
            md += "**\(i + 1). [\(line.timeText)] \(who):** \(head)\n\n"
            appendSourceEcho(&md, source: source, target: target,
                             enabled: record.showsSourceEcho)
        }
        return md
    }

    private static func appendInsights(_ md: inout String, _ snapshots: [InsightSnapshot]) {
        guard !snapshots.isEmpty else { return }
        md += "## AI Insight History\n\n"
        for snapshot in snapshots.sorted(by: { $0.requestedAt < $1.requestedAt }) {
            do {
                let value = try snapshot.decoded()
                md += "### \(value.input.configuration.title) · \(value.input.kind.label)\n\n"
                md += "> Cutoff: \(DateFormat.insightTimestamp.string(from: value.input.requestedAt)) · All original source through cutoff · \(value.input.sources.count) sections\n\n"
                if value.input.containsProvisional { md += "> Includes provisional recognition.\n\n" }
                md += value.result.conclusion + "\n\n"
                for point in value.result.points { md += "- \(point)\n" }
                md += "\n"
                if let summary = value.result.summary {
                    for part in summary.parts {
                        md += "#### \(part.title)\n\n"
                        if part.items.isEmpty { md += part.emptyMessage + "\n" }
                        for item in part.items { md += "- \(item)\n" }
                        md += "\n"
                    }
                }
            } catch {
                md += "Saved insight could not be decoded: \(error.localizedDescription)\n\n"
            }
        }
        md += "---\n\n"
    }

    /// Append the source text as a blockquote — only for a translated meeting (`enabled`)
    /// and when the source genuinely differs from the translation, so we never echo the
    /// same line twice.
    private static func appendSourceEcho(_ md: inout String, source: String,
                                         target: String, enabled: Bool) {
        guard enabled, !source.isEmpty, source != target else { return }
        md += "> \(source)\n\n"
    }

    // MARK: - Save panel

    /// Export the live transcript. `showsSourceEcho` is the current meeting's mode flag
    /// (`languagePair.needsTranslation`).
    static func exportWithPanel(store: CaptionStore, showsSourceEcho: Bool) {
        presentSavePanel(markdown: markdown(store: store, showsSourceEcho: showsSourceEcho))
    }

    /// Export a saved meeting's transcript.
    static func exportRecord(_ record: MeetingRecord) {
        presentSavePanel(markdown: markdown(record: record))
    }

    /// Present a save panel and write `md`, surfacing any write failure to the user
    /// rather than silently swallowing it.
    private static func presentSavePanel(markdown md: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "meeting-transcript-\(DateFormat.fileStamp.string(from: Date())).md"
        panel.canCreateDirectories = true
        panel.title = "Export Meeting Transcript"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
