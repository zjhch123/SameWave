import SwiftUI

struct MeetingVocabularyView: View {
    let record: MeetingRecord
    let editor: VocabularyEditorStore
    var manageContext: () -> Void

    var body: some View {
        VocabularyEditorView(editor: editor, meetingDocuments: record.orderedDocuments.map(\.source),
                             manageContext: manageContext)
    }
}
