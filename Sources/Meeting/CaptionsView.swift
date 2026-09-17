import SwiftUI

/// Renders chronological speaker turns, using source until a translation arrives.
struct CaptionsView: View {
    let store: CaptionStore
    var isListening = false
    /// A status / error line (permission prompt, model download, capture failure) shown
    /// in the empty state. MeetingStage also keeps it visible above populated captions.
    var statusMessage: String = ""
    /// True when source and target languages match, so the recognized text IS the caption
    /// and there is no translation. The large primary line already shows that source, so the muted
    /// "source" echo underneath would be a verbatim duplicate — suppress it entirely.
    /// (Equality alone can't be relied on: an OPEN section's growing interim briefly
    /// diverges from the last native-caption snapshot, flashing the echo.)
    var hideSourceEcho: Bool = false

    // Apple design-system palette (mirrors the reference index.html tokens). Only the
    // tokens actually used across the app are kept.
    static let bg          = Color.white                                    // #ffffff
    static let surface     = Color(red: 0.961, green: 0.961, blue: 0.969)   // #f5f5f7
    static let fg          = Color(red: 0.114, green: 0.114, blue: 0.122)   // #1d1d1f
    static let muted       = Color(red: 0.431, green: 0.431, blue: 0.451)   // #6e6e73
    static let meta        = Color(red: 0.525, green: 0.525, blue: 0.545)   // #86868b
    static let borderSoft  = Color(red: 0.910, green: 0.910, blue: 0.929)   // #e8e8ed
    static let accent      = Color(red: 0.0,   green: 0.443, blue: 0.890)   // #0071e3
    static let danger      = Color(red: 0.863, green: 0.149, blue: 0.149)   // #dc2626

    /// HH:mm formatter for the per-line spoken time.
    static func timeString(_ date: Date) -> String { DateFormat.clock.string(from: date) }

    @State private var followsLatestCaption = true
    @State private var isUserScrolling = false
    @State private var pendingFollow = true
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    private struct ScrollMetrics: Equatable {
        let contentHeight: CGFloat
        let viewportHeight: CGFloat
        let visibleBottom: CGFloat
        var isNearBottom: Bool { contentHeight - visibleBottom <= 32 }
    }

    var body: some View {
        // Empty stage → a truly centered placeholder (not pinned inside the scroll
        // view, which the dock's safe-area inset would otherwise push off-center).
        if store.sections.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.bg)
        } else {
            transcriptScroll
        }
    }

    private var transcriptScroll: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(store.paragraphLayout.paragraphs) { paragraph in
                    CaptionParagraphRow(sections: paragraph.sectionIDs.compactMap { store.section(id: $0) },
                                        hideSourceEcho: hideSourceEcho)
                }
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.bg)
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            if isUserScrolling { pendingFollow = false }
        }
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(contentHeight: geometry.contentSize.height,
                          viewportHeight: geometry.containerSize.height,
                          visibleBottom: geometry.visibleRect.maxY)
        } action: { old, new in
            if isUserScrolling {
                followsLatestCaption = new.isNearBottom
            } else if old.contentHeight != new.contentHeight || old.viewportHeight != new.viewportHeight {
                if followsLatestCaption {
                    pendingFollow = true
                    scrollPosition.scrollTo(edge: .bottom)
                }
            } else if pendingFollow {
                if new.isNearBottom { pendingFollow = false }
                else { scrollPosition.scrollTo(edge: .bottom) }
            } else {
                followsLatestCaption = new.isNearBottom
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isListening ? "waveform" : "text.bubble")
                .font(.system(size: 34))
                .foregroundStyle(Self.meta.opacity(0.5))
            Text(isListening ? String(localized: "Listening…") : String(localized: "Click Start below to begin live captions"))
                .font(.system(size: 15))
                .foregroundStyle(Self.muted)
            // Surface setup status / errors (permission, model download, capture
            // failure) so they're visible instead of silently dropped.
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Self.meta)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

}

struct CaptionParagraphRow: View {
    let sections: [Section]
    let hideSourceEcho: Bool

    private var source: String { TranscriptText.join(sections.map(\.sourceText)) }

    private func primaryText(for section: Section) -> String {
        let target = section.targetText.trimmed
        return hideSourceEcho || section.translationState == .failed || target.isEmpty
            ? section.sourceText : target
    }

    private var primary: AttributedString {
        var result = AttributedString()
        var previous = ""
        for section in sections {
            let text = primaryText(for: section)
            guard !text.isEmpty else { continue }
            var span = AttributedString(TranscriptText.separator(between: previous, and: text) + text)
            span.foregroundColor = section.contentState == .open ? CaptionsView.muted : CaptionsView.fg
            result.append(span)
            previous = text
        }
        return result
    }

    var body: some View {
        let mine = sections.first?.speaker == .mine
        let failed = sections.contains { $0.translationState == .failed }
        let showsSource = sections.contains { primaryText(for: $0) != $0.sourceText }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(mine ? String(localized: "You") : String(localized: "Speaker"))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(mine ? CaptionsView.accent : CaptionsView.meta)
                if let first = sections.first {
                    Text(CaptionsView.timeString(first.startedAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CaptionsView.meta.opacity(0.7))
                }
                if failed {
                    Text("Translation failed · Showing source text")
                        .font(.system(size: 11))
                        .foregroundStyle(CaptionsView.danger)
                }
            }

            Text(primary)
                .font(.system(size: 25, weight: .medium))
                .tracking(-0.2)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(CaptionHeightReservation())

            if !hideSourceEcho && !source.isEmpty {
                Text(source)
                    .font(.system(size: 14))
                    .foregroundStyle(CaptionsView.muted)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showsSource ? 1 : 0)
                    .accessibilityHidden(!showsSource)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CaptionHeightReservation())
        .transaction { $0.animation = nil }
    }
}

private struct CaptionHeightReservation: ViewModifier {
    @State private var reservedHeight: CGFloat = 0
    @State private var measuredWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content.fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if abs(size.width - measuredWidth) > 1 {
                    measuredWidth = size.width
                    reservedHeight = size.height
                } else { reservedHeight = max(reservedHeight, size.height) }
            }
            .frame(minHeight: reservedHeight, alignment: .topLeading)
    }
}
