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
        // Lead with the cached AI insight (if the user generated one) so a shared minute
        // opens with the summary before the full transcript.
        appendInsight(&md, record.insight)
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

    /// Append the cached insight as a "## AI Insights" section (topic / suggestions / todos /
    /// decisions). No-op when there's no cached insight, so exports of un-analyzed
    /// meetings are unchanged.
    private static func appendInsight(_ md: inout String, _ insight: InsightResult?) {
        guard let insight, !insight.isEmpty else { return }
        md += "## AI Insights\n\n"
        if !insight.topic.trimmed.isEmpty {
            md += "**Topic:** \(insight.topic)\n\n"
        }
        if let answer = insight.answer?.trimmed, !answer.isEmpty {
            md += "**Suggested Answer:** \(answer)\n\n"
        }
        if !insight.suggestions.isEmpty {
            md += "**Suggestions:**\n\n"
            for s in insight.suggestions { md += "- \(s)\n" }
            md += "\n"
        }
        if !insight.todos.isEmpty {
            md += "**Action Items:**\n\n"
            for t in insight.todos { md += "- \(t.who): \(t.what)\n" }
            md += "\n"
        }
        if !insight.decisions.isEmpty {
            md += "**Decisions:**\n\n"
            for d in insight.decisions { md += "- \(d)\n" }
            md += "\n"
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
