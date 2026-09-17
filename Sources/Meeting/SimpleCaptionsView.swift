import SwiftUI

struct SimpleCaptionsView: View {
    let coordinator: CaptureCoordinator
    let onShowFullWindow: () -> Void
    @State private var showingStatus = false
    @State private var showingBackgroundOpacity = false
    @AppStorage("simpleModeBackgroundOpacity") private var backgroundOpacity = 0.85

    private var statusMessage: String {
        coordinator.statusMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if !statusMessage.isEmpty { status }
                Divider()
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(backgroundOpacity))
            CaptionsView(store: coordinator.store,
                         isListening: coordinator.isRunning,
                         statusMessage: coordinator.statusMessage,
                         hideSourceEcho: !coordinator.languagePair.needsTranslation,
                         backgroundColor: CaptionsView.bg.opacity(backgroundOpacity))
        }
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand {
            showingStatus = false
            showingBackgroundOpacity = false
        }
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
