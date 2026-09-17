import SwiftUI

struct SimpleCaption: Identifiable, Equatable {
    let id: Int
    let speaker: Speaker
    let text: String
    let translationState: TranslationState
    let startedAt: Date

    static func latest(in sections: [Section], languagePair: MeetingLanguagePair) -> [Self] {
        sections.reversed().lazy.filter { !$0.sourceText.isEmpty }.prefix(2).reversed().map {
            Self(id: $0.id, speaker: $0.speaker,
                text: languagePair.needsTranslation ? $0.targetText.trimmed : $0.sourceText,
                translationState: languagePair.needsTranslation ? $0.translationState : .done,
                startedAt: $0.startedAt)
        }
    }

}

struct SimpleCaptionReading {
    private(set) var heldCaptions: [SimpleCaption]?

    mutating func hold(_ captions: [SimpleCaption]) {
        if heldCaptions == nil { heldCaptions = captions }
    }

    mutating func followLatest() { heldCaptions = nil }
}

struct SimpleCaptionsView: View {
    let coordinator: CaptureCoordinator
    let onShowFullWindow: () -> Void
    @State private var reading = SimpleCaptionReading()
    @State private var isUserScrolling = false
    @State private var showingStatus = false
    @State private var showingBackgroundOpacity = false
    @AppStorage("simpleModeBackgroundOpacity") private var backgroundOpacity = 0.85

    private var captions: [SimpleCaption] {
        SimpleCaption.latest(in: coordinator.store.sections, languagePair: coordinator.languagePair)
    }

    private var statusMessage: String {
        coordinator.statusMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !statusMessage.isEmpty {
                status
            }
            Divider()
            ScrollViewReader { proxy in
                if reading.heldCaptions != nil {
                    HStack {
                        Text("Reading earlier text")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Latest subtitles") {
                            reading.followLatest()
                            proxy.scrollTo("simple.bottom", anchor: .bottom)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                if captions.isEmpty && reading.heldCaptions == nil {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(reading.heldCaptions ?? captions) { caption in
                                captionRow(caption)
                            }
                            Color.clear.frame(height: 1).id("simple.bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onScrollPhaseChange { _, phase in
                        isUserScrolling = phase == .interacting || phase == .decelerating
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 16
                    } action: { _, aboveBottom in
                        if aboveBottom && isUserScrolling { reading.hold(captions) }
                    }
                    .onKeyPress(keys: [.upArrow, .pageUp, .home]) { _ in
                        reading.hold(captions)
                        return .ignored
                    }
                    .onChange(of: captions) { _, _ in
                        if reading.heldCaptions == nil { proxy.scrollTo("simple.bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor).opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand {
            showingStatus = false
            showingBackgroundOpacity = false
        }
        .onChange(of: coordinator.selectedRecordID) { _, _ in reading.followLatest() }
        .onChange(of: coordinator.languagePair) { _, _ in reading.followLatest() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Simple Mode")
                .font(.system(size: 12, weight: .semibold))
                .fixedSize()
            Spacer(minLength: 0)
            CaptureControls(coordinator: coordinator, compact: true)
                .disabled(coordinator.isTransitioning || !coordinator.isRunning)
                .fixedSize()
            Button { showingBackgroundOpacity.toggle() } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .frame(width: 26, height: 26)
            }
            .help("Background Opacity")
            .accessibilityLabel("Background Opacity")
            .accessibilityIdentifier("simple.backgroundOpacity")
            .popover(isPresented: $showingBackgroundOpacity) {
                SimpleBackgroundOpacityControls(opacity: $backgroundOpacity)
            }
            Button(action: onShowFullWindow) {
                ViewThatFits(in: .horizontal) {
                    Label("Show Full Window", systemImage: "macwindow")
                    Image(systemName: "macwindow")
                }
            }
            .font(.system(size: 11))
            .help("Show Full Window")
            .accessibilityLabel("Show Full Window")
            .accessibilityIdentifier("simple.showFullWindow")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var status: some View {
        Button { showingStatus.toggle() } label: {
            Text(statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .help(statusMessage)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .popover(isPresented: $showingStatus) {
            Text(statusMessage)
                .textSelection(.enabled)
                .padding(16)
                .frame(width: 320, alignment: .leading)
        }
        .accessibilityIdentifier("simple.status")
    }

    private var emptyState: some View {
        Group {
            if coordinator.isPaused { Text("Paused") }
            else if coordinator.isTransitioning { Text(coordinator.statusMessage) }
            else { Text("Waiting for speech…") }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func captionRow(_ caption: SimpleCaption) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label(caption.speaker == .mine ? "Me" : "Other party",
                    systemImage: caption.speaker == .mine ? "mic.fill" : "speaker.wave.2.fill")
                Text(caption.startedAt, style: .time)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            if !caption.text.isEmpty {
                Text(verbatim: caption.text)
                    .font(.system(size: 25, weight: .medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if caption.translationState != .failed {
                Text("Translating…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if caption.translationState == .failed {
                Label("Translation unavailable", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SimpleBackgroundOpacityControls: View {
    @Binding var opacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Background Opacity")
                Spacer()
                Text(opacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            Slider(value: $opacity, in: 0...1, step: 0.05) {
                Text("Background Opacity")
            }
            .labelsHidden()
            .accessibilityValue(opacity.formatted(.percent.precision(.fractionLength(0))))
            .accessibilityIdentifier("simple.backgroundOpacitySlider")
        }
        .font(.callout)
        .padding(16)
        .frame(width: 260)
    }
}
