import SwiftData
import SwiftUI

struct HistoryDetailView: View {
    let record: MeetingRecord
    var showRefined: Bool = false

    var body: some View {
        let transcript = HistoryTranscript(record: record, showRefined: showRefined)
        HistoryTranscriptView(text: transcript.attributedText(hideSourceEcho: !record.showsSourceEcho))
            .background(CaptionsView.bg)
    }
}

struct HistoryTranscript {
    let paragraphs: [CaptionParagraph]
    private let sections: [Int: Section]

    init(record: MeetingRecord, showRefined: Bool = false) {
        let lines = record.lines.sorted { $0.orderIndex < $1.orderIndex }
        var originals: [Section] = []
        var displayed: [Int: Section] = [:]
        originals.reserveCapacity(lines.count)
        displayed.reserveCapacity(lines.count)
        for line in lines {
            var section = Section(id: line.sectionId, speaker: Speaker(persistedValue: line.speaker))
            section.committedSource = [line.sourceText]
            section.startedAt = line.spokenAt
            section.contentState = .sealed
            originals.append(section)
            section.committedSource = [line.displaySource(refined: showRefined)]
            section.targetText = line.displayTarget(refined: showRefined)
            let previous = displayed.updateValue(section, forKey: section.id)
            precondition(previous == nil, "Saved transcript Section IDs must be unique")
        }
        var layout = CaptionParagraphLayout()
        layout.update(sections: originals)
        paragraphs = layout.paragraphs
        sections = displayed
    }

    func displayedSections(in paragraph: CaptionParagraph) -> [Section] {
        paragraph.sectionIDs.map { sections[$0]! }
    }
}
