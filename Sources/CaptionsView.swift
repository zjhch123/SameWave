import SwiftUI

/// The visual content of the floating caption overlay.
/// Shows the last few finalized lines plus the in-progress (dimmed) line,
/// inside a height-capped scroll view that auto-follows the newest content.
struct CaptionsView: View {
    let store: CaptionStore

    /// A cheap digest of everything currently visible. When it changes we scroll
    /// to the bottom so the newest line/gist is always in view.
    private var scrollSignal: String {
        let last = store.lines.last.map { "\($0.chinese)#\($0.english)" } ?? ""
        return "\(store.lines.count)|\(last)|\(store.block.chinese)|\(store.block.english.count)|\(store.interim?.chinese ?? "")|\(store.interim?.english ?? "")"
    }

    private static let bottomAnchor = "captions.bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    content
                    // Zero-height marker we always scroll to.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .scrollContentBackground(.hidden)
            // Fixed top/bottom gutter (does NOT scroll): a draggable black strip so
            // the panel can be moved even though the scroll area eats drag gestures.
            .padding(.vertical, 14)
            .onChange(of: scrollSignal) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        // Let drags move the whole panel (panel has isMovableByWindowBackground).
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var content: some View {
        // Finalized history lines. Now that everything lives in a scroll view we
        // render them ALL (bounded by the store's maxLines) so nothing silently
        // vanishes — important for Chinese mode, where every sentence is a line
        // here (no context block). Dimmed only when an English live block sits
        // below them; in Chinese mode they ARE the content, shown bright.
        let dimHistory = !store.block.isEmpty
        ForEach(store.lines) { line in
            lineView(line, dim: dimHistory)
        }

        // Current block: committed sentences (bright) with the in-progress
        // sentence folded in as a dim trailing run — so a finalized sentence
        // never "jumps" up from a separate floating line into the paragraph;
        // it just brightens in place at the tail as the block grows down.
        if !store.block.isEmpty {
            blockView(store.block, gist: store.interim)
        } else if let interim = store.interim {
            // No block yet (session start, or Chinese-meeting mode): show the
            // live line on its own.
            if !interim.chinese.isEmpty {
                lineView(interim, dim: true)
            } else if !interim.english.isEmpty {
                Text(interim.english)
                    .font(.system(size: 14, weight: .regular).italic())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }

        if store.lines.isEmpty && store.block.isEmpty && store.interim == nil {
            Text(store.isRunning ? "聆听中…" : "点击菜单栏图标开始")
                .foregroundStyle(.white.opacity(0.55))
                .font(.system(size: 15, weight: .medium))
        }
    }

    /// The current context block: whole-block Chinese (bright) + English source,
    /// with the in-progress sentence's rough gist appended dim at the tail so the
    /// reading order stays top→down and a finalized sentence never jumps upward.
    @ViewBuilder
    private func blockView(_ block: CaptionBlock, gist: CaptionLine?) -> some View {
        // The live sentence's gist trails the committed Chinese, dimmer.
        let liveZh = gist?.chinese ?? ""
        let liveEn = gist?.english ?? ""
        VStack(alignment: .leading, spacing: 3) {
            (
                Text(block.chinese.isEmpty ? "翻译中…" : block.chinese)
                    .foregroundStyle(.white)
                + Text(liveZh.isEmpty ? "" : (block.chinese.isEmpty ? liveZh : " " + liveZh))
                    .foregroundStyle(.white.opacity(0.55))
            )
            .font(.system(size: 21, weight: .semibold))
            .textSelection(.enabled)

            let en = [block.joinedEnglish, liveEn].filter { !$0.isEmpty }.joined(separator: " ")
            if !en.isEmpty {
                Text(en)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
            }
        }
        .animation(.easeOut(duration: 0.15), value: block.chinese)
        .animation(.easeOut(duration: 0.15), value: liveZh)
    }

    @ViewBuilder
    private func lineView(_ line: CaptionLine, dim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Chinese is the primary read; English is the secondary reference.
            Text(line.chinese.isEmpty ? " " : line.chinese)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(dim ? 0.6 : 1.0))
                .textSelection(.enabled)
            if !line.english.isEmpty {
                Text(line.english)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(dim ? 0.4 : 0.6))
                    .textSelection(.enabled)
            }
        }
        .animation(.easeOut(duration: 0.12), value: line.chinese)
    }
}
