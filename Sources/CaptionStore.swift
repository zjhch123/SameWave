import Foundation
import Observation

/// A single caption line: the recognized English plus its Chinese translation.
struct CaptionLine: Identifiable, Equatable {
    let id = UUID()
    var english: String
    var chinese: String
    /// `false` while speech recognition is still refining this line (interim hypothesis).
    var isFinal: Bool
}

/// The "current block": the recent window of English sentences translated
/// TOGETHER for context, shown as one refining paragraph (English sentences
/// listed, Chinese is the whole-block translation that updates as new sentences
/// arrive). When the block fills up, its oldest content is sedimented into
/// `lines` (history) and a fresh block begins.
struct CaptionBlock: Equatable {
    var english: [String] = []   // sentences in the window, oldest→newest
    var chinese: String = ""     // whole-block translation (refines over time)

    var isEmpty: Bool { english.isEmpty }
    var joinedEnglish: String { english.joined(separator: " ") }
}

/// Central observable store the overlay renders from, and every pipeline stage writes to.
///
/// Threading: the speech recognition callback and the translation task both hop
/// to the main actor before mutating this, so the SwiftUI overlay updates safely.
@MainActor
@Observable
final class CaptionStore {
    /// Finalized/sedimented lines, oldest→newest. The overlay shows the tail.
    private(set) var lines: [CaptionLine] = []

    /// The line currently being spoken (interim). Rendered dimmed under the finalized tail.
    private(set) var interim: CaptionLine?

    /// The current context block (recent window, translated together).
    private(set) var block = CaptionBlock()

    /// High-level status shown in the menu bar / overlay header.
    var status: String = "Idle"

    /// True while a capture session is running.
    var isRunning: Bool = false

    /// Safety ceiling only — real meetings never approach this. Text is cheap
    /// (~0.5 KB/line, so 50000 lines ≈ 25 MB) and the overlay uses a LazyVStack
    /// that renders only on-screen rows, so a long transcript stays smooth. This
    /// exists just so an all-day runaway session can't grow truly unbounded.
    private let maxLines = 50000

    // MARK: - Context block (local, whole-block refining translation)

    /// Append a newly finalized English sentence to the current block.
    func appendToBlock(english: String) {
        let text = english.trimmingCharacters(in: .whitespacesAndNewlines)
        interim = nil
        guard !text.isEmpty else { return }
        block.english.append(text)
    }

    /// Update the whole-block Chinese translation (refines the visible paragraph).
    func setBlockChinese(_ chinese: String) {
        block.chinese = chinese
    }

    /// Chinese-meeting mode: the recognized Chinese IS the caption (no translation,
    /// no context block). Append it directly as a finalized line.
    func appendChineseLine(_ chinese: String) {
        let zh = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        interim = nil
        guard !zh.isEmpty else { return }
        let line = CaptionLine(english: "", chinese: zh, isFinal: true)
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    /// Native Chinese mode: live (volatile) recognition text — shown as the
    /// in-progress interim line, replaced when the finalized line commits.
    func updateInterimChineseNative(_ chinese: String) {
        let zh = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zh.isEmpty else { interim = nil; return }
        if interim == nil {
            interim = CaptionLine(english: "", chinese: zh, isFinal: false)
        } else {
            interim?.chinese = zh
        }
    }

    /// Sediment the current block into history and start fresh. Called when the
    /// window slides past its size — the block becomes one stable history entry
    /// (English = all its sentences joined, Chinese = its final translation).
    func sedimentBlock() {
        guard !block.isEmpty else { return }
        let line = CaptionLine(english: block.joinedEnglish,
                               chinese: block.chinese, isFinal: true)
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        block = CaptionBlock()
    }

    // MARK: - Interim (local hypothesis) / legacy per-line

    /// Replace the interim (in-progress) English hypothesis. Chinese is filled in later.
    func updateInterim(english: String) {
        guard !english.isEmpty else { interim = nil; return }
        if interim == nil {
            interim = CaptionLine(english: english, chinese: "", isFinal: false)
        } else {
            interim?.english = english
        }
    }

    /// Fill in the rough (provisional) Chinese gist for the in-progress sentence,
    /// shown dim under the bright block. No-ops if the sentence already committed
    /// (interim cleared) so a late gist can't resurrect a finished line.
    func setInterimChinese(_ chinese: String) {
        guard interim != nil else { return }
        interim?.chinese = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Promote the interim text to a finalized line (translation may still be pending).
    /// Returns the id so the translator can fill in Chinese asynchronously.
    @discardableResult
    func finalizeInterim(english: String) -> UUID? {
        let text = english.trimmingCharacters(in: .whitespacesAndNewlines)
        interim = nil
        guard !text.isEmpty else { return nil }
        let line = CaptionLine(english: text, chinese: "", isFinal: true)
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        return line.id
    }

    /// Fill in (or update) the Chinese translation for a finalized line.
    func setTranslation(_ chinese: String, for id: UUID) {
        if let idx = lines.firstIndex(where: { $0.id == id }) {
            lines[idx].chinese = chinese
        }
    }

    func clear() {
        lines.removeAll()
        interim = nil
        block = CaptionBlock()
    }
}
