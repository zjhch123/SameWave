import AppKit
import Foundation

/// Exports the captured captions as a Markdown transcript (Chinese + English).
@MainActor
enum TranscriptExporter {

    /// Build the Markdown from the store's history + current block.
    static func markdown(store: CaptionStore) -> String {
        var entries = store.lines
        // Include the still-open block so nothing is lost.
        if !store.block.isEmpty {
            entries.append(CaptionLine(english: store.block.joinedEnglish,
                                       chinese: store.block.chinese, isFinal: true))
        }

        var md = "# 会议字幕纪要\n\n"
        md += "> 由 MeetingCaptions 本地生成 · 共 \(entries.count) 段\n\n---\n\n"
        for (i, line) in entries.enumerated() {
            let zh = line.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
            let en = line.english.trimmingCharacters(in: .whitespacesAndNewlines)
            if !zh.isEmpty { md += "**\(i + 1).** \(zh)\n\n" }
            if !en.isEmpty { md += "> \(en)\n\n" }
        }
        return md
    }

    /// Show a save panel and write the transcript.
    static func exportWithPanel(store: CaptionStore) {
        let md = markdown(store: store)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "会议纪要-\(timestamp()).md"
        panel.canCreateDirectories = true
        panel.title = "导出会议纪要"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? md.data(using: .utf8)?.write(to: url)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }
}
