import SwiftUI
import UniformTypeIdentifiers

/// Shared vocabulary editing for Meeting Preparation and Settings sheets.
struct VocabularyEditorView: View {
    @Bindable var editor: VocabularyEditorStore
    var isEmbeddedInSettings = false
    var meetingDocuments: [VocabularySourceDocument] = []
    var manageContext: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsNavigation.self) private var settingsNavigation
    @State private var choosingFiles = false
    @State private var position = ScrollPosition()
    @State private var trackingScroll = false
    @FocusState private var focus: VocabularyEditorStore.Focus?

    static var markdownContentTypes: [UTType] {
        [UTType(filenameExtension: "md") ?? .plainText,
         UTType(filenameExtension: "markdown") ?? .plainText]
    }
    private var importer: VocabularyImportController { editor.importer }
    private var isActive: Bool { !isEmbeddedInSettings || settingsNavigation.selectedTab == .vocabulary }
    private var documents: [VocabularySourceDocument] {
        editor.scope == .meeting ? meetingDocuments : editor.documents
    }
    private var showsSuggestions: Bool {
        importer.isRunning || importer.canRetry || !importer.candidates.isEmpty || importer.savedMessage != nil || importer.saveError != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isEmbeddedInSettings {
                editorHeading.padding(.horizontal, 20).padding(.vertical, 16)
                Divider()
            }
            Form {
                extraction
                if showsSuggestions { VocabularySuggestionsView(editor: editor, focus: $focus) }
                VocabularySavedTermsView(editor: editor, focus: $focus)
            }
            .formStyle(.grouped)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                if trackingScroll { editor.scrollOffset = max(0, offset) }
            }
            if !isEmbeddedInSettings {
                Divider()
                HStack {
                    Text("Drafts are kept until you quit the app.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }
                }.padding(12)
            }
        }
        .frame(width: 600, height: isEmbeddedInSettings ? nil : 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: Self.markdownContentTypes,
                      allowsMultipleSelection: true, onCompletion: editor.chooseFiles)
        .onAppear {
            let offset = editor.scrollOffset
            if isActive { focus = editor.focusedField }
            if offset > 0 { position.scrollTo(y: offset) }
            trackingScroll = true
        }
        .onChange(of: focus) { _, value in
            if isActive, let value { editor.focusedField = value }
        }
        .onChange(of: isActive) { _, active in
            focus = active ? editor.focusedField : nil
        }
        .onDisappear { trackingScroll = false }
        .onChange(of: importer.candidates.count, initial: true) { _, count in
            if count > 10 { editor.showsBottomActions = true }
        }
        .onExitCommand {
            guard isActive else { return }
            if editor.editingPhrase != nil { editor.cancelEditing(); editor.focusedField = nil; focus = nil }
            else { dismiss() }
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard isActive, press.modifiers.contains(.command) else { return .ignored }
            if focus == .manual { editor.addTerms() }
            else if focus == .saved { editor.saveEdit() }
            else { importer.saveSelected() }
            return .handled
        }
    }

    private var editorHeading: some View {
        HStack {
            Text(editor.title).font(.headline)
            Spacer()
            Text(editor.scopeLabel).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var extraction: some View {
        SwiftUI.Section {
            HStack {
                Text(editor.scope == .meeting
                     ? String(localized: "\(documents.count) documents in Context")
                     : String(localized: "\(documents.count) temporary files selected"))
                    .foregroundStyle(.secondary)
                Spacer()
                if editor.scope == .meeting {
                    Button(documents.isEmpty ? String(localized: "Go to Context") : String(localized: "Manage Context")) { manageContext?() }
                } else {
                    Button("Choose Markdown…") { choosingFiles = true }
                        .disabled(editor.isLoadingFiles)
                }
            }
            if editor.scope == .meeting && !documents.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(documents.enumerated()), id: \.offset) { _, document in
                        VocabularyDocumentRow(document: document)
                    }
                }
            }
            if editor.scope == .personal && !documents.isEmpty {
                DisclosureGroup("Selected files", isExpanded: $editor.filesExpanded) {
                    VStack(spacing: 6) {
                        ForEach(Array(documents.enumerated()), id: \.offset) { index, document in
                            VocabularyDocumentRow(document: document) { editor.removeDocument(at: index) }
                        }
                    }.padding(.top, 6)
                }
            }
            if editor.isLoadingFiles { Text("Reading local files…").foregroundStyle(.secondary) }
            if let error = editor.fileError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack(spacing: 8) {
                if importer.isRunning {
                    ProgressView().controlSize(.small)
                    Text(importer.state == .preparing ? String(localized: "Preparing documents…") : String(localized: "Extracting vocabulary…"))
                    Spacer()
                    if !importer.requests.isEmpty {
                        Text("\(importer.completedCount)/\(importer.requests.count) parts")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button("Stop") { importer.stop() }
                } else if importer.canRetry {
                    Text("\(importer.incompleteCount) parts remaining").foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry Incomplete") { importer.retryIncomplete() }
                } else {
                    Button("Extract Vocabulary") {
                        editor.showsBottomActions = false
                        importer.start(documents: documents)
                    }
                    .disabled(documents.isEmpty || !importer.isAvailable || !importer.candidates.isEmpty || editor.isLoadingFiles)
                    .help(importer.candidates.isEmpty ? String(localized: "Extract terms from selected Markdown") : String(localized: "Save or discard suggestions before extracting again"))
                    if !importer.isAvailable {
                        Button(importer.settingsActionTitle) { settingsNavigation.openAISettings() }
                            .buttonStyle(.borderless)
                    }
                    Spacer(minLength: 0)
                }
            }
            if importer.state == .reviewing && importer.discoveredCount == 0 {
                Text("No new terms found.").foregroundStyle(.secondary)
            }
            if let message = importer.generationError {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        } header: {
            Text("Extract from Markdown")
        } footer: {
            if importer.isRunning || importer.canRetry {
                Text("Retry uses the original files.")
            }
        }
    }
}

private struct VocabularySuggestionsView: View {
    let editor: VocabularyEditorStore
    @FocusState<VocabularyEditorStore.Focus?>.Binding var focus: VocabularyEditorStore.Focus?
    private var importer: VocabularyImportController { editor.importer }
    private var selectedCount: Int { importer.candidates.filter(\.isSelected).count }
    private var allSelected: Bool { selectedCount == importer.candidates.count }

    var body: some View {
        @Bindable var importer = importer
        return SwiftUI.Section {
            suggestionActions
            if !importer.candidates.isEmpty || importer.isRunning || importer.canRetry {
                if importer.candidates.isEmpty {
                    Text(importer.isRunning ? String(localized: "Terms will appear here as they’re found.") : String(localized: "No suggestions received. Retry or discard this extraction.")).foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach($importer.candidates) { $candidate in
                            VocabularyCandidateRow(candidate: $candidate)
                                .focused($focus, equals: .candidate(candidate.id))
                                .frame(height: 36)
                        }
                    }
                }
                if editor.showsBottomActions && !importer.candidates.isEmpty {
                    suggestionActions
                }
            }
        } header: {
            HStack {
                Text("Suggested Terms")
                Text("\(importer.candidates.count)").foregroundStyle(.secondary)
            }
        } footer: {
            Text("Not saved · Add to \(editor.title)")
        }
    }

    private var suggestionActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !importer.candidates.isEmpty || importer.isRunning || importer.canRetry {
                HStack(spacing: 10) {
                    Button(allSelected ? String(localized: "Deselect All") : String(localized: "Select All")) { importer.selectAll(!allSelected) }
                        .buttonStyle(.borderless).disabled(importer.candidates.isEmpty)
                    Button("Discard Suggestions") { importer.discardSuggestions() }
                        .buttonStyle(.borderless).disabled(importer.isRunning)
                        .help(importer.isRunning ? String(localized: "Stop extraction before discarding suggestions") : String(localized: "Discard unsaved suggestions"))
                    Spacer(minLength: 0)
                    Button("Add to Vocabulary") { importer.saveSelected() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCount == 0 || importer.hasInvalidSelection)
                }
                Text("\(selectedCount) selected").font(.caption).foregroundStyle(.secondary)
            }
            if importer.hasInvalidSelection {
                Text("Selected terms must be single-line phrases of 1–100 characters.")
                    .font(.caption).foregroundStyle(.red)
            }
            if let error = importer.saveError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            } else if let message = importer.savedMessage {
                Label(message, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct VocabularySavedTermsView: View {
    @Bindable var editor: VocabularyEditorStore
    @FocusState<VocabularyEditorStore.Focus?>.Binding var focus: VocabularyEditorStore.Focus?

    var body: some View {
        SwiftUI.Section {
            HStack {
                Text(editor.scopeLabel).foregroundStyle(.secondary)
                Spacer()
                if editor.isAddingTerms {
                    Button("Hide") { editor.isAddingTerms = false; editor.focusedField = nil; focus = nil }
                    Button("Add Terms") { editor.addTerms() }
                        .buttonStyle(.borderedProminent)
                        .disabled(editor.manualPhrases.isEmpty || editor.hasInvalidManualInput)
                } else {
                    Button("Add Terms…") { editor.isAddingTerms = true; focus = .manual }
                }
            }
            if let message = editor.vocabularyError {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            } else if let message = editor.vocabularyMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if editor.isAddingTerms {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One phrase per line. Paste several terms at once.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $editor.manualText)
                        .font(.body).scrollContentBackground(.hidden)
                        .padding(6).frame(height: 86)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        .focused($focus, equals: .manual)
                        .accessibilityLabel("New vocabulary terms")
                    if editor.hasInvalidManualInput {
                        Text("Each term must be a single line of 1–100 characters.").font(.caption).foregroundStyle(.red)
                    }
                }
            }
            if editor.phrases.isEmpty {
                Text("No saved terms yet.").foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(editor.phrases, id: \.self) { phrase in
                        VocabularySavedTermRow(phrase: phrase, editor: editor, focus: $focus)
                    }
                }
            }
        } header: {
            HStack {
                Text("Saved Vocabulary")
                Text("\(editor.phrases.count)").foregroundStyle(.secondary)
            }
        } footer: {
            Text("English recognition uses saved terms at Start or Resume.")
        }
    }
}

private struct VocabularySavedTermRow: View {
    let phrase: String
    @Bindable var editor: VocabularyEditorStore
    @FocusState<VocabularyEditorStore.Focus?>.Binding var focus: VocabularyEditorStore.Focus?

    var body: some View {
        HStack(spacing: 8) {
            if editor.editingPhrase == phrase {
                TextField("Term", text: $editor.editedText).textFieldStyle(.roundedBorder)
                    .labelsHidden().multilineTextAlignment(.leading)
                    .focused($focus, equals: .saved).onSubmit { editor.saveEdit() }
                if !VocabularyGenerator.isValidPhrase(editor.editedText) {
                    Text("Invalid term").font(.caption).foregroundStyle(.red)
                        .help("Enter a single-line term of 1–100 characters.")
                        .accessibilityLabel("Enter a single-line term of 1–100 characters.")
                }
                Button("Save") { editor.saveEdit() }
                    .disabled(!VocabularyGenerator.isValidPhrase(editor.editedText))
                Button("Cancel") { editor.cancelEditing(); editor.focusedField = nil; focus = nil }
            } else {
                Text(phrase).textSelection(.enabled).lineLimit(2)
                Spacer()
                Button { editor.beginEditing(phrase); focus = .saved } label: { Image(systemName: "pencil") }
                    .disabled(editor.editingPhrase != nil)
                    .accessibilityLabel("Edit \(phrase)").help("Edit \(phrase)")
                Button { editor.remove(phrase) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove \(phrase)").help("Remove \(phrase)")
            }
        }.buttonStyle(.borderless).frame(height: 36)
    }
}

struct VocabularyCandidateRow: View {
    @Binding var candidate: VocabularyCandidate

    var body: some View {
        HStack {
            Toggle("Select \(candidate.text)", isOn: $candidate.isSelected)
                .toggleStyle(.checkbox).labelsHidden()
            TextField("Term", text: $candidate.text).textFieldStyle(.roundedBorder)
                .labelsHidden().multilineTextAlignment(.leading)
                .accessibilityLabel("Edit \(candidate.originalPhrase)")
        }
    }
}
