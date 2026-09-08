import SwiftUI

struct MeetingContextView: View {
    let record: MeetingRecord
    let history: MeetingHistoryStore
    var focusRequest = 0
    @State private var choosingFiles = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var error: String?
    @FocusState private var attachFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Context").font(.system(size: 13, weight: .semibold))
                Text("\(record.documents.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Attach Markdown…") { choosingFiles = true }
                    .controlSize(.small).disabled(loadingTask != nil).focused($attachFocused)
            }
            Text("Markdown for vocabulary extraction only.").font(.caption).foregroundStyle(.secondary)
            ForEach(record.orderedDocuments) { document in
                VocabularyDocumentRow(document: document.source) {
                    do { try history.removeAttachment(document); error = nil }
                    catch { self.error = String(localized: "Could not remove document: \(error.localizedDescription)") }
                }
            }
            if loadingTask != nil { ProgressView(String(localized: "Reading local files…")).controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text("Local copies · UTF-8 Markdown · 3 MB per file · 30 MB per meeting")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: VocabularyEditorView.markdownContentTypes,
                      allowsMultipleSelection: true) { result in
            loadingTask = Task {
                defer { loadingTask = nil }
                do {
                    let documents = try await VocabularyDocumentLoader.load(result.get())
                    try Task.checkCancellation()
                    guard let owner = try history.record(id: record.id) else { return }
                    try history.attach(documents, to: owner)
                    error = nil
                } catch is CancellationError { return }
                catch {
                    let nsError = error as NSError
                    if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .onChange(of: focusRequest) { _, _ in attachFocused = true }
        .onDisappear { loadingTask?.cancel() }
    }
}
