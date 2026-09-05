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
                    Text("审核新词").font(.headline)
                    Spacer()
                    Button("全选") { controller.selectAll(true) }
                    Button("全不选") { controller.selectAll(false) }
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
        .confirmationDialog("放弃本次未保存的新词和进度，选择其他文件？",
                            isPresented: $isConfirmingReplacement) {
            Button("选择其他文件", role: .destructive) { isChoosingMarkdown = true }
        } message: {
            Text("已保存到词表的内容不会受影响；取消文件选择仍会保留本次结果。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.state == .idle ? "从 Markdown 生成词表" : "生成与审核")
                    .font(.title2.weight(.semibold))
                Spacer()
                if controller.isRunning { Button("停止") { controller.stop() } }
            }
            if controller.state == .preparing {
                Text("正在读取文件…").foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            } else if !controller.requests.isEmpty {
                Text("已完成 \(controller.completedCount)/\(controller.requests.count)，发现 \(controller.discoveredCount) 个新词")
                    .foregroundStyle(.secondary)
                if controller.isRunning {
                    ProgressView(value: Double(controller.completedCount), total: Double(controller.requests.count))
                    if let attempt = controller.attempts.last {
                        Text(attemptStatus(attempt)).font(.caption).foregroundStyle(.secondary)
                    }
                } else if controller.incompleteCount > 0 {
                    Text(controller.failedCount > 0
                         ? "\(controller.failedCount) 个请求失败，已生成的新词仍可保存。"
                         : "已停止，已生成的新词仍可保存。")
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
            Text(controller.isRunning ? "新词会陆续显示在这里" :
                    (controller.state == .idle ? "选择文件，提取专有名词" : "暂无待审核的新词"))
                .font(.headline)
            Text(controller.isRunning ? "可以边生成边审核，不必等全部完成。" :
                    "只展示与现有词表去重后的结果。")
                .foregroundStyle(.secondary)
            if controller.state == .idle {
                Text("文件正文会发送到当前配置的 AI 服务。")
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
                    Button(controller.requests.isEmpty ? "选择文件" : "选择其他文件") {
                        if !controller.candidates.isEmpty || controller.incompleteCount > 0 {
                            isConfirmingReplacement = true
                        } else {
                            isChoosingMarkdown = true
                        }
                    }
                    .disabled(!controller.isConfigured)
                }
                if controller.canRetry {
                    Button("重试未完成部分") { controller.retryIncomplete() }
                }
                Spacer()
                Button("添加并保存 \(controller.selectedPhrases.count) 个词") {
                    controller.saveSelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.selectedPhrases.isEmpty || controller.hasInvalidSelection)
            }
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("请求详情") {
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
            Text("耗时从请求发起计至完整响应及校验结束，包含网络与服务端处理。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func attemptStatus(_ attempt: VocabularyAttempt) -> String {
        if case .failed = attempt.outcome, attempt.number <= VocabularyGenerator.maximumRetriesPerBatch {
            return "请求 \(attempt.batchNumber) 未成功，准备第 \(attempt.number)/2 次重试…"
        }
        return attempt.number == 1
            ? "正在处理请求 \(attempt.batchNumber)…"
            : "正在重试请求 \(attempt.batchNumber)（\(attempt.number - 1)/2）…"
    }
}

private struct VocabularyCandidateRow: View {
    @Binding var candidate: VocabularyCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle("选择 \(candidate.text)", isOn: $candidate.isSelected)
                    .toggleStyle(.checkbox).labelsHidden()
                TextField("词条", text: $candidate.text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("编辑 \(candidate.originalPhrase)")
            }
            if candidate.isSelected && !VocabularyGenerator.isValidPhrase(candidate.text) {
                Text("请输入 1–100 字符的单行词条。")
                    .font(.caption).foregroundStyle(.red)
            }
            DisclosureGroup("来源") {
                VStack(alignment: .leading, spacing: 6) {
                    if candidate.text != candidate.originalPhrase {
                        Text("原始提取：\(candidate.originalPhrase)").font(.caption)
                    }
                    if candidate.sources.isEmpty {
                        Text("原文中未找到此拼写，请核对。")
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
                Text("请求 \(attempt.batchNumber) · \(attempt.number == 1 ? "首次" : "重试 \(attempt.number - 1)/2")")
                Spacer()
                if let duration = attempt.duration {
                    Text(String(format: "%.1f 秒", duration)).monospacedDigit()
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(String(format: "%.0f 秒…", max(0, context.date.timeIntervalSince(attempt.startedAt))))
                            .monospacedDigit()
                    }
                }
            }
            switch attempt.outcome {
            case .running: Text("等待完整响应").foregroundStyle(.secondary)
            case .succeeded: Text("成功").foregroundStyle(.secondary)
            case .cancelled: Text("已停止").foregroundStyle(.secondary)
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
