import SwiftUI

/// Renders an `InsightResult` as a stack of native cards, in the app's Apple design
/// language (reusing `CaptionsView`'s palette tokens). Shared by the live right-side
/// Inspector and the history detail view, so insights look identical wherever they
/// appear. There is deliberately NO markdown/HTML rendering: the LLM returns structured
/// fields and each renders as its own typed card — selection, scrolling, and theming
/// come for free.
///
/// This view is a plain `VStack` (no internal ScrollView) so each host controls its own
/// scrolling — the Inspector wraps it in a ScrollView; the history detail embeds it
/// inside the transcript's existing ScrollView without nesting.
struct InsightCardsView: View {
    let result: InsightResult
    let state: InsightEngine.State
    /// Whether the app-wide AI service is configured. Otherwise show the configuration prompt.
    var isConfigured: Bool
    /// Optional action to open Settings, wired by the host (⌘, is always available too).
    var onOpenSettings: (() -> Void)? = nil
    /// When true (the live Inspector), placeholder/empty states fill the available height
    /// and center — so "Waiting for Conversation" sits in the middle of the panel, not the top-left.
    /// When false (embedded in history's transcript scroll), everything stays a plain
    /// top-aligned content block so it doesn't fight the host's layout.
    var centersPlaceholder: Bool = false

    /// The current display bucket, so we know whether to center (placeholder) or
    /// top-align (real cards).
    private var isPlaceholderState: Bool {
        if !isConfigured { return true }
        if case .error = state { return true }
        return result.isEmpty   // waiting / analyzing with nothing yet
    }

    var body: some View {
        Group {
            if isPlaceholderState && centersPlaceholder {
                // Center the placeholder in the whole panel (no scroll needed — it's a
                // single short block).
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if centersPlaceholder {
                // Real cards in the live Inspector: own the vertical scroll here so the
                // placeholder branch above can use the full height.
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                // Embedded in history's own scroll — a plain top-aligned block.
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case _ where !isConfigured:
                notConfigured
            case .error(let e):
                errorCard(e)
            case .idle where result.isEmpty:
                waiting
            case .generating where result.isEmpty:
                analyzing
            default:
                cards
                if case .generating = state { analyzingInline }
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder private var cards: some View {
        if !result.topic.trimmed.isEmpty {
            card(icon: "text.magnifyingglass", title: "Current Topic") {
                Text(result.topic)
                    .font(.system(size: 13))
                    .foregroundStyle(CaptionsView.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        if let answer = result.answer?.trimmed, !answer.isEmpty {
            // Highlighted — "The other participant asked a question; here is a suggested answer".
            card(icon: "bubble.left.and.text.bubble.right", title: "Suggested Answer",
                 tint: CaptionsView.accent) {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundStyle(CaptionsView.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        if !result.suggestions.isEmpty {
            card(icon: "lightbulb", title: "Suggestions") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.suggestions.enumerated()), id: \.offset) { _, s in
                        bullet(s)
                    }
                }
            }
        }
        if !result.todos.isEmpty {
            card(icon: "checklist", title: "Action Items") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.todos) { todo in
                        HStack(alignment: .top, spacing: 6) {
                            Text(todo.who)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CaptionsView.accent)
                            Text(todo.what)
                                .font(.system(size: 13))
                                .foregroundStyle(CaptionsView.fg)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        if !result.decisions.isEmpty {
            card(icon: "checkmark.seal", title: "Decisions") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.decisions.enumerated()), id: \.offset) { _, d in
                        bullet(d)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var notConfigured: some View {
        placeholder(icon: "gearshape",
                    title: "Insights Require an AI Service",
                    detail: "Open Settings → AI Services to configure topic summaries, suggestions, and action items. The same configuration is used for transcript refinement, meeting titles, and vocabulary generation.",
                    actionLabel: "Configure AI Services")
    }

    private var waiting: some View {
        placeholder(icon: "sparkles",
                    title: "Waiting for Conversation",
                    detail: "Insights appear automatically as your meeting progresses.")
    }

    private var analyzing: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Analyzing…")
                .font(.system(size: 13))
                .foregroundStyle(CaptionsView.muted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    /// Small inline "still refining" hint shown under existing cards during a re-gen.
    private var analyzingInline: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Updating…")
                .font(.system(size: 11))
                .foregroundStyle(CaptionsView.meta)
        }
        .padding(.top, 2)
    }

    private func errorCard(_ e: LLMError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(CaptionsView.danger)
                Text("Insights Unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CaptionsView.fg)
            }
            Text(e.errorDescription ?? "Unknown error")
                .font(.system(size: 12))
                .foregroundStyle(CaptionsView.muted)
                .fixedSize(horizontal: false, vertical: true)
            if e == .notConfigured || e == .unauthorized, let onOpenSettings {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CaptionsView.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(CaptionsView.danger.opacity(0.06)))
    }

    // MARK: - Building blocks

    private func placeholder(icon: String, title: String, detail: String,
                             actionLabel: String? = nil) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(CaptionsView.accent.opacity(0.45))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CaptionsView.muted)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(CaptionsView.muted.opacity(0.8))
                .multilineTextAlignment(.center)
            if let actionLabel, let onOpenSettings {
                Button(actionLabel, action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CaptionsView.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 12)
    }

    /// One insight card: an icon+title header over its content, on a soft surface.
    @ViewBuilder
    private func card<Content: View>(icon: String, title: String,
                                     tint: Color = CaptionsView.meta,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(tint)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint == CaptionsView.accent
                      ? CaptionsView.accent.opacity(0.06)
                      : CaptionsView.surface))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.system(size: 13))
                .foregroundStyle(CaptionsView.meta)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(CaptionsView.fg)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
