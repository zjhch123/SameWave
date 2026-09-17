import Foundation

enum TranscriptText {
    static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    }

    static func separator(between left: String, and right: String) -> String {
        guard let last = left.last, let first = right.first else { return "" }
        if last.isWhitespace || first.isWhitespace { return "" }
        if ".,!?;:，。！？；：、)]}）】》”’".contains(first)
            || "([{（【《“‘".contains(last) { return "" }
        if containsChinese(String(last)) || containsChinese(String(first))
            || "，。！？；：、".contains(last) { return "" }
        return " "
    }

    static func join(_ fragments: [String]) -> String {
        fragments.map(\.trimmed).filter { !$0.isEmpty }.reduce("") { result, fragment in
            result + separator(between: result, and: fragment) + fragment
        }
    }
}

struct CaptionParagraph: Identifiable, Equatable, Sendable {
    let id: Int
    var sectionIDs: [Int]
}

struct CaptionParagraphLayout: Equatable, Sendable {
    private(set) var paragraphs: [CaptionParagraph] = []

    mutating func update(sections: [Section]) {
        let byID = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
        paragraphs = paragraphs.compactMap { paragraph in
            var retained = paragraph
            retained.sectionIDs.removeAll { byID[$0] == nil }
            return retained.sectionIDs.isEmpty ? nil : retained
        }
        let assigned = Set(paragraphs.flatMap(\.sectionIDs))
        for section in sections where !assigned.contains(section.id) {
            if let last = paragraphs.last,
               let previous = last.sectionIDs.last.flatMap({ byID[$0] }),
               previous.speaker == section.speaker,
               section.startedAt.timeIntervalSince(previous.startedAt) < 20 {
                let source = TranscriptText.join(last.sectionIDs.compactMap { byID[$0]?.sourceText })
                let chinese = TranscriptText.containsChinese(source)
                let endsSentence = SpeechHypothesis().revising(previous.sourceText).last?.endsSentence == true
                if source.count < (chinese ? 96 : 240)
                    || (source.count < (chinese ? 144 : 360) && !endsSentence) {
                    paragraphs[paragraphs.count - 1].sectionIDs.append(section.id)
                    continue
                }
            }
            paragraphs.append(CaptionParagraph(id: section.id, sectionIDs: [section.id]))
        }
    }
}
