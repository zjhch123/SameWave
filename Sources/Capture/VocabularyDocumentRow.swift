import SwiftUI

/// The same file metadata in Context and both vocabulary hosts; the owner supplies removal.
struct VocabularyDocumentRow: View {
    let document: VocabularySourceDocument
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(document.fileName).lineLimit(1).truncationMode(.middle).help(document.fileName)
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: Int64(document.content.utf8.count), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary).fixedSize()
            if let remove {
                Button(action: remove) { Image(systemName: "trash").frame(width: 24, height: 24) }
                    .buttonStyle(.borderless).help("Remove \(document.fileName)")
                    .accessibilityLabel("Remove \(document.fileName)")
            }
        }.font(.system(size: 12))
    }
}
