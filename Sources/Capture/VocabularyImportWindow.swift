import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VocabularyImportWindow: View {
    static let windowID = "vocabulary-import"
    let controller: VocabularyImportController
    @State private var isChoosingMarkdown = false
    @State private var isConfirmingReplacement = false

    static var markdownContentTypes: [UTType] {
        [UTType(filenameExtension: "md") ?? .plainText,
         UTType(filenameExtension: "markdown") ?? .plainText]
    }

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 14) {
            header
            if controller.candidates.isEmpty {
                emptyState
            } else {
                HStack {
                    Text("Review New Terms").font(.headline)
                    Spacer()
                    Button("Select All") { controller.selectAll(true) }
                    Button("Deselect All") { controller.selectAll(false) }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach($controller.candidates) { $candidate in
                            VocabularyCandidateRow(candidate: $candidate)
                        }
                    }
                    .padding(10)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
            if !controller.attempts.isEmpty { diagnostics }
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 460)
        .background(VocabularyWindowCloseObserver(onClose: controller.close))
        .fileImporter(
            isPresented: $isChoosingMarkdown,
            allowedContentTypes: Self.markdownContentTypes,
            allowsMultipleSelection: true
        ) { controller.handleFileSelection($0) }
        .confirmationDialog("Discard unsaved terms and progress, and choose other files?",
                            isPresented: $isConfirmingReplacement) {
            Button("Choose Other Files", role: .destructive) { isChoosingMarkdown = true }
        } message: {
            Text("Saved vocabulary is unaffected. Cancelling the file picker keeps the current results.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.state == .idle ? "Generate Vocabulary from Markdown" : "Generate and Review")
                    .font(.title2.weight(.semibold))
                Spacer()
                if controller.isRunning { Button("Stop") { controller.stop() } }
            }
            if controller.state == .preparing {
                Text("Reading files…").foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            } else if !controller.requests.isEmpty {
                Text("Completed \(controller.completedCount)/\(controller.requests.count) · New terms: \(controller.discoveredCount)")
                    .foregroundStyle(.secondary)
                if controller.isRunning {
                    ProgressView(value: Double(controller.completedCount), total: Double(controller.requests.count))
                    if let attempt = controller.attempts.last {
                        Text(attemptStatus(attempt)).font(.caption).foregroundStyle(.secondary)
                    }
                } else if controller.incompleteCount > 0 {
                    Text(controller.failedCount > 0
                         ? "Failed requests: \(controller.failedCount). You can still save the generated terms."
                         : "Stopped. You can still save the generated terms.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if case .failed(let message) = controller.state {
                Text(message).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(controller.isRunning ? "New terms will appear here" :
                    (controller.state == .idle ? "Choose files to extract proper names" : "No new terms to review"))
                .font(.headline)
            Text(controller.isRunning ? "You can review terms while generation continues." :
                    "Only terms absent from your saved vocabulary are shown.")
                .foregroundStyle(.secondary)
            if controller.state == .idle {
                Text("File contents will be sent to your configured AI service.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = controller.savedMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            }
            HStack(spacing: 10) {
                if !controller.isRunning {
                    Button(controller.requests.isEmpty ? "Choose Files" : "Choose Other Files") {
                        if !controller.candidates.isEmpty || controller.incompleteCount > 0 {
                            isConfirmingReplacement = true
                        } else {
                            isChoosingMarkdown = true
                        }
                    }
                    .disabled(!controller.isConfigured)
                }
                if controller.canRetry {
                    Button("Retry Incomplete Requests") { controller.retryIncomplete() }
                }
                Spacer()
                Button("Add and Save (\(controller.selectedPhrases.count))") {
                    controller.saveSelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.selectedPhrases.isEmpty || controller.hasInvalidSelection)
            }
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Request Details") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(controller.attempts) { attempt in
                        VocabularyAttemptRow(attempt: attempt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 140)
            Text("Timing runs from request start through the complete response and validation, including network and server processing.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func attemptStatus(_ attempt: VocabularyAttempt) -> String {
        if case .failed = attempt.outcome, attempt.number <= VocabularyGenerator.maximumRetriesPerBatch {
            return "Request \(attempt.batchNumber) failed. Preparing retry \(attempt.number)/2…"
        }
        return attempt.number == 1
            ? "Processing request \(attempt.batchNumber)…"
            : "Retrying request \(attempt.batchNumber) (\(attempt.number - 1)/2)…"
    }
}

private struct VocabularyCandidateRow: View {
    @Binding var candidate: VocabularyCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle("Select \(candidate.text)", isOn: $candidate.isSelected)
                    .toggleStyle(.checkbox).labelsHidden()
                TextField("Term", text: $candidate.text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Edit \(candidate.originalPhrase)")
            }
            if candidate.isSelected && !VocabularyGenerator.isValidPhrase(candidate.text) {
                Text("Enter a single-line term of 1–100 characters.")
                    .font(.caption).foregroundStyle(.red)
            }
            DisclosureGroup("Source") {
                VStack(alignment: .leading, spacing: 6) {
                    if candidate.text != candidate.originalPhrase {
                        Text("Extracted term: \(candidate.originalPhrase)").font(.caption)
                    }
                    if candidate.sources.isEmpty {
                        Text("This spelling was not found in the source. Please verify it.")
                    }
                    ForEach(candidate.sources, id: \.self) { source in
                        Text(source.fileName).font(.caption.weight(.medium))
                        Text(source.text).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .font(.caption).padding(.leading, 22)
        }
    }
}

private struct VocabularyAttemptRow: View {
    let attempt: VocabularyAttempt

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Request \(attempt.batchNumber) · \(attempt.number == 1 ? "Initial" : "Retry \(attempt.number - 1)/2")")
                Spacer()
                if let duration = attempt.duration {
                    Text(String(format: "%.1f s", duration)).monospacedDigit()
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(String(format: "%.0f s…", max(0, context.date.timeIntervalSince(attempt.startedAt))))
                            .monospacedDigit()
                    }
                }
            }
            switch attempt.outcome {
            case .running: Text("Waiting for the complete response").foregroundStyle(.secondary)
            case .succeeded: Text("Succeeded").foregroundStyle(.secondary)
            case .cancelled: Text("Stopped").foregroundStyle(.secondary)
            case .failed(let message): Text(message).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
    }
}

/// Observe the actual window close, not View disappearance (e.g. state changes).
private struct VocabularyWindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView(onClose: onClose) }
    func updateNSView(_ nsView: ObserverView, context: Context) { nsView.onClose = onClose }

    final class ObserverView: NSView {
        var onClose: @MainActor () -> Void

        init(onClose: @escaping @MainActor () -> Void) {
            self.onClose = onClose
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                    name: NSWindow.willCloseNotification, object: window)
            }
        }

        @objc private func windowWillClose(_ notification: Notification) { onClose() }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
