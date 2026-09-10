import SwiftUI

struct MeetingPreparationView: View {
    let record: MeetingRecord
    let history: MeetingHistoryStore
    let editor: VocabularyEditorStore
    let onDone: (() -> Void)?
    @State private var title: String
    @State private var error: String?
    @State private var managingVocabulary = false
    @State private var editingDefinition: InsightDefinition?
    @State private var addingDefinition = false
    @State private var showingArchive = false

    init(record: MeetingRecord, history: MeetingHistoryStore,
         editor: VocabularyEditorStore, onDone: (() -> Void)? = nil) {
        self.record = record
        self.history = history
        self.editor = editor
        self.onDone = onDone
        _title = State(initialValue: record.userTitle)
    }

    private var importer: VocabularyImportController { editor.importer }
    @State private var contextFocusRequest = 0
    @State private var returningToContext = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Meeting Preparation").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    if let onDone {
                        Button("Done", action: onDone).keyboardShortcut(.defaultAction)
                    }
                }
                Text("Optional. Start whenever you’re ready.")
                    .font(.system(size: 13)).foregroundStyle(CaptionsView.muted)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            .frame(maxWidth: 640)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                        preparationCard {
                            HStack {
                                Text("Meeting title").font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if title == record.userTitle { Text("Saved").font(.caption).foregroundStyle(CaptionsView.muted) }
                            }
                            HStack(spacing: 8) {
                                TextField("Meeting title", text: $title).textFieldStyle(.roundedBorder)
                                    .onSubmit(saveTitle)
                                Button("Save", action: saveTitle).disabled(title == record.userTitle)
                            }
                        }
                        preparationCard {
                            MeetingContextView(record: record, history: history, focusRequest: contextFocusRequest)
                        }.id("context")
                        preparationCard {
                            LabeledContent {
                                HStack {
                                    Spacer(minLength: 8)
                                    Button("Manage Vocabulary…") { managingVocabulary = true }.controlSize(.small)
                                        .fixedSize()
                                }
                            } label: {
                                Text("Vocabulary")
                                Text("\(record.vocabulary.count) saved terms · This meeting")
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if importer.isRunning {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("Extracting vocabulary · \(importer.completedCount)/\(importer.requests.count)")
                                }.font(.caption).foregroundStyle(CaptionsView.muted)
                            } else if !importer.candidates.isEmpty {
                                Text("\(importer.candidates.count) suggested terms · Open Manage to choose")
                                    .font(.caption).foregroundStyle(CaptionsView.accent)
                            } else if importer.canRetry {
                                Text("Extraction incomplete · Open Manage to retry")
                                    .font(.caption).foregroundStyle(CaptionsView.muted)
                            } else if case .failed = importer.state {
                                Text("Extraction failed · Open Manage to try again")
                                    .font(.caption).foregroundStyle(.red)
                            }
                            if record.vocabulary.isEmpty {
                                Text("Add terms yourself or extract them from Context.")
                                    .font(.system(size: 12)).foregroundStyle(CaptionsView.muted)
                            } else {
                                VocabularyPreviewLayout {
                                    ForEach(Array(record.confirmedVocabulary.prefix(12)), id: \.self) { phrase in
                                        Text(phrase).lineLimit(1).font(.system(size: 11))
                                            .help(phrase)
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(.white, in: RoundedRectangle(cornerRadius: 5))
                                    }
                                    if record.vocabulary.count > 12 {
                                        Text("+\(record.vocabulary.count - 12)").font(.caption).foregroundStyle(CaptionsView.muted)
                                    }
                                }
                            }
                        }
                        preparationCard {
                            HStack {
                                Text("AI Insights").font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button { addingDefinition = true } label: { Label("Add…", systemImage: "plus") }
                                    .controlSize(.small)
                            }
                            ForEach(record.orderedDefinitions) { definition in
                                Divider()
                                LabeledContent {
                                    HStack {
                                        Spacer(minLength: 8)
                                        Button("Edit") { editingDefinition = definition }.controlSize(.small)
                                            .fixedSize()
                                    }
                                } label: {
                                    Text(definition.title).fixedSize(horizontal: false, vertical: true)
                                    Text(definition.automaticallyUpdates ? String(localized: "Automatic") : String(localized: "Manual"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if record.definitions.isEmpty {
                                Text("Add an insight when you need one.").font(.callout).foregroundStyle(CaptionsView.muted)
                            }
                            if !record.archivedInsightConfigurations.isEmpty {
                                Button("Saved results from removed insights…") { showingArchive = true }
                                    .buttonStyle(.plain).font(.caption).foregroundStyle(CaptionsView.accent)
                            }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 640)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .foregroundStyle(CaptionsView.fg)
                .onChange(of: contextFocusRequest) { _, _ in proxy.scrollTo("context", anchor: .top) }
                .sheet(isPresented: $managingVocabulary, onDismiss: {
                    if returningToContext { contextFocusRequest += 1; returningToContext = false }
                }) {
                    MeetingVocabularyView(record: record, editor: editor, manageContext: {
                        returningToContext = true
                        managingVocabulary = false
                    })
                        .modifier(SettingsSheet())
                }
                .sheet(item: $editingDefinition) { definition in
                    InsightDefinitionEditor(record: record, history: history, definition: definition)
                        .modifier(SettingsSheet())
                }
                .sheet(isPresented: $addingDefinition) {
                    InsightDefinitionEditor(record: record, history: history, definition: nil)
                        .modifier(SettingsSheet())
                }
                .sheet(isPresented: $showingArchive) {
                    ArchivedInsightResults(record: record).modifier(SettingsSheet())
                }
            }
        }
        .foregroundStyle(CaptionsView.fg)
    }

    private func preparationCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(CaptionsView.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func saveTitle() {
        do {
            record.userTitle = title.trimmed
            try history.save()
            title = record.userTitle
            error = nil
        } catch { self.error = String(localized: "Could not save title: \(error.localizedDescription)") }
    }
}

private struct VocabularyPreviewLayout: Layout {
    private let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

struct ArchivedInsightResults: View {
    let record: MeetingRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Insight Results").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("These insights were removed from preparation. Their saved versions remain available.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(record.archivedInsightConfigurations, id: \.id) { configuration in
                        InsightResultCard(meetingID: record.id, configuration: configuration,
                            snapshots: record.insightSnapshots.filter { $0.definitionID == configuration.id })
                    }
                }.padding(20)
            }
        }.frame(width: 500, height: 440)
    }
}
