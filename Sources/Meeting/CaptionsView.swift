import SwiftUI

/// The live transcript stage: a centered single-column text stream rendered in
/// section-id order. The active speaker gets the only open section; a finalized
/// sentence from the other speaker seals it and opens the next section. Interims from
/// the non-active stream cannot reorder the transcript.
///
/// Each section shows a speaker label (mine → "You" in accent blue; remote → "Speaker"
/// in meta gray), the selected target language as the large primary line, and the
/// source text as a small muted secondary line. A still-translating section shows a subtle
/// "Translating" indicator (spec Rule B — translation state affects only the UI hint).
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

    /// Shown while a sealed section's translation is still in flight, and as the
    /// placeholder for the primary line before any translation lands.
    static let translatingHint = "Translating…"

    /// HH:mm formatter for the per-line spoken time.
    static func timeString(_ date: Date) -> String { DateFormat.clock.string(from: date) }

    /// Cheap change signal so the scroll view knows to re-pin to the bottom.
    private var scrollSignal: String {
        guard let last = store.sections.last else { return "0" }
        return "\(store.sections.count)|\(last.id)|\(last.targetText.count)|\(last.committedSource.count)|\(last.interimSource.count)|\(translationSignal(last.translationState))"
    }

    private func translationSignal(_ state: TranslationState) -> Int {
        switch state {
        case .pending: 0
        case .translating: 1
        case .done: 2
        case .failed: 3
        }
    }

    private static let bottomAnchor = "captions.bottom"

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
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(store.sections) { section in
                        transcriptBlock(section)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)               // center the 800pt column
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 16)                     // the dock occupies its own layout row
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.bg)
            .onChange(of: scrollSignal) { _, _ in
                // NB: a plain scrollTo, NOT withAnimation. withAnimation opens a
                // transaction that captures EVERY view change in the same render
                // pass — including the active section's text refining — and
                // cross-dissolves it. That transaction was the flicker. A direct
                // scrollTo keeps the feed pinned to the bottom without animating text.
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onAppear { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isListening ? "waveform" : "text.bubble")
                .font(.system(size: 34))
                .foregroundStyle(Self.meta.opacity(0.5))
            Text(isListening ? "Listening…" : "Click Start below to begin live captions")
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

    // MARK: - One section

    @ViewBuilder
    private func transcriptBlock(_ section: Section) -> some View {
        let mine = (section.speaker == .mine)
        let target = section.targetText.trimmed
        let source = section.sourceText
        let failed = section.translationState == .failed
        let translating = section.contentState == .sealed
            && (section.translationState == .pending || section.translationState == .translating)
        let primary = failed ? source : target
        VStack(alignment: .leading, spacing: 6) {
            // Speaker label + spoken time + translation status (UI-only).
            HStack(spacing: 8) {
                Text(mine ? "You" : "Speaker")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(mine ? Self.accent : Self.meta)
                Text(Self.timeString(section.startedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Self.meta.opacity(0.7))
                if translating {
                    Text(Self.translatingHint)
                        .font(.system(size: 11))
                        .foregroundStyle(Self.meta.opacity(0.8))
                } else if failed {
                    Text("Translation failed · Showing source text")
                        .font(.system(size: 11))
                        .foregroundStyle(Self.danger)
                }
            }

            // Translation is primary when available. A failed translation falls back
            // to the source as the primary line instead of looking permanently busy.
            Text(primary.isEmpty ? Self.translatingHint : primary)
                .font(.system(size: 25, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(primary.isEmpty ? Self.muted : Self.fg)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Source text = small muted secondary line. Never shown in same-language mode
            // (it would duplicate the primary), nor when it's identical to the target.
            if !failed && !hideSourceEcho && !source.isEmpty && source != target {
                Text(source)
                    .font(.system(size: 14))
                    .foregroundStyle(Self.muted)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Hard-disable any ambient/inherited animation on this block: text updates
        // (translation refining in place) must snap, never cross-dissolve. This is
        // the belt to the scroll's suspenders — even if some other view change opens
        // an animation transaction, the transcript text stays flicker-free.
        .transaction { $0.animation = nil }
    }
}
