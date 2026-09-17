import AppKit
import SwiftUI

struct HistoryTranscriptView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> HistoryTextScrollView {
        let view = HistoryTextScrollView()
        view.setText(text)
        return view
    }

    func updateNSView(_ view: HistoryTextScrollView, context: Context) {
        view.setText(text)
    }
}

final class HistoryTextScrollView: NSScrollView {
    let transcriptTextView: NSTextView
    private let storage = NSTextStorage()
    private let textLayout = NSLayoutManager()
    private let container = NSTextContainer(containerSize: .zero)
    private var textChanged = true
    private var measuredWidth: CGFloat = -1
    private var textHeight: CGFloat = 0

    init() {
        storage.addLayoutManager(textLayout)
        textLayout.addTextContainer(container)
        textLayout.allowsNonContiguousLayout = false
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        transcriptTextView = NSTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        backgroundColor = .white
        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = true
        transcriptTextView.isRichText = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.isVerticallyResizable = false
        transcriptTextView.drawsBackground = false
        transcriptTextView.usesFontPanel = false
        transcriptTextView.allowsUndo = false
        documentView = transcriptTextView
    }

    required init?(coder: NSCoder) {
        fatalError("HistoryTextScrollView requires programmatic initialization")
    }

    func setText(_ text: NSAttributedString) {
        guard !storage.isEqual(to: text) else { return }
        storage.setAttributedString(text)
        textChanged = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let viewport = contentSize
        guard viewport.width > 0 else { return }
        let origin = contentView.bounds.origin
        if textChanged || measuredWidth != viewport.width {
            let inset = max(40, (viewport.width - 800) / 2)
            transcriptTextView.textContainerInset = NSSize(width: inset, height: 24)
            container.containerSize = NSSize(width: max(1, viewport.width - inset * 2),
                                             height: .greatestFiniteMagnitude)
            textLayout.ensureLayout(for: container)
            textHeight = ceil(textLayout.usedRect(for: container).height)
            measuredWidth = viewport.width
            textChanged = false
        }
        let size = NSSize(width: viewport.width, height: max(viewport.height, textHeight + 64))
        if transcriptTextView.frame.size != size {
            transcriptTextView.setFrameSize(size)
            contentView.scroll(to: NSPoint(x: 0, y: min(origin.y, max(0, size.height - viewport.height))))
            reflectScrolledClipView(contentView)
        }
    }
}

extension HistoryTranscript {
    @MainActor
    func attributedText(hideSourceEcho: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let foreground = NSColor(CaptionsView.fg)
        let muted = NSColor(CaptionsView.muted)
        let meta = NSColor(CaptionsView.meta)
        let headerStyle = paragraphStyle(lineSpacing: 0, after: 6)
        let primaryStyle = paragraphStyle(lineSpacing: 4, after: 6)
        let primaryEndStyle = paragraphStyle(lineSpacing: 4, after: 24)
        let primaryLastStyle = paragraphStyle(lineSpacing: 4, after: 0)
        let sourceStyle = paragraphStyle(lineSpacing: 2, after: 24)
        let sourceLastStyle = paragraphStyle(lineSpacing: 2, after: 0)
        for (index, paragraph) in paragraphs.enumerated() {
            let sections = displayedSections(in: paragraph)
            let first = sections[0]
            let last = index == paragraphs.count - 1
            let source = TranscriptText.join(sections.map(\.sourceText))
            let primary = TranscriptText.join(sections.map { section in
                let target = section.targetText.trimmed
                return hideSourceEcho || target.isEmpty ? section.sourceText : target
            })
            let showsSource = !hideSourceEcho && !source.isEmpty && source != primary
            let speaker = first.speaker == .mine ? String(localized: "You") : String(localized: "Speaker")
            result.append(NSAttributedString(string: speaker + "  ", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .kern: 0.5,
                .foregroundColor: first.speaker == .mine ? NSColor(CaptionsView.accent) : meta,
                .paragraphStyle: headerStyle
            ]))
            result.append(NSAttributedString(string: CaptionsView.timeString(first.startedAt) + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: meta.withAlphaComponent(0.7), .paragraphStyle: headerStyle
            ]))
            result.append(NSAttributedString(string: primary + (showsSource || !last ? "\n" : ""), attributes: [
                .font: NSFont.systemFont(ofSize: 25, weight: .medium), .kern: -0.2,
                .foregroundColor: foreground,
                .paragraphStyle: showsSource ? primaryStyle : (last ? primaryLastStyle : primaryEndStyle)
            ]))
            if showsSource {
                result.append(NSAttributedString(string: source + (last ? "" : "\n"), attributes: [
                    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: muted,
                    .paragraphStyle: last ? sourceLastStyle : sourceStyle
                ]))
            }
        }
        return result
    }

    private func paragraphStyle(lineSpacing: CGFloat, after spacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = spacing
        return style
    }
}
