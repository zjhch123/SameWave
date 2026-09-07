import Foundation
import NaturalLanguage

/// Keeps display ownership while a recognizer revises a cumulative hypothesis.
/// Word matching ignores punctuation/case, but displayed text preserves both.
struct SpeechHypothesis {
    struct Word {
        let text: String
        let key: String
        var sectionID: Int?
    }

    var words: [Word] = []

    func revising(_ text: String) -> [Word] {
        var revised = Self.tokenize(text)
        let difference = revised.map(\.key).difference(from: words.map(\.key))
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let matches = Array(zip(words.indices.filter { !removed.contains($0) },
                                revised.indices.filter { !inserted.contains($0) }))
        var oldStart = 0
        var newStart = 0
        for (oldEnd, newEnd) in matches + [(words.count, revised.count)] {
            let isTail = oldEnd == words.count && newEnd == revised.count
            for offset in newStart..<newEnd {
                let replaced = oldStart + offset - newStart
                if replaced < oldEnd {
                    revised[offset].sectionID = words[replaced].sectionID
                } else if !isTail {
                    // An insertion before an existing word is an ASR correction.
                    revised[offset].sectionID = words[oldEnd].sectionID
                }
                // Unmatched trailing words extend the utterance and acquire the
                // current display turn, rather than extending a sealed paragraph.
            }
            if oldEnd < words.count {
                revised[newEnd].sectionID = words[oldEnd].sectionID
            }
            oldStart = oldEnd + 1
            newStart = newEnd + 1
        }
        return revised
    }

    private static func tokenize(_ text: String) -> [Word] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let ranges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        return ranges.enumerated().map { index, range in
            let start = index == 0 ? text.startIndex : range.lowerBound
            let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : text.endIndex
            return Word(text: String(text[start..<end]),
                        key: String(text[range]).lowercased(), sectionID: nil)
        }
    }
}
