import SwiftUI

struct MainView: View {
    let coordinator: CaptureCoordinator

    @State private var sidebarOpen = true
    @State private var selectedRecord: MeetingRecord?
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 280

    var body: some View {
        HStack(spacing: 0) {
            if sidebarOpen {
                MeetingSidebar(coordinator: coordinator, selectedRecord: $selectedRecord)
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            MeetingStage(
                coordinator: coordinator,
                sidebarOpen: $sidebarOpen,
                selectedRecord: $selectedRecord
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            InspectorResizeHandle(width: $inspectorWidth, minWidth: 240, maxWidth: 620)
            InsightInspector(coordinator: coordinator, selectedRecord: $selectedRecord)
                .frame(width: inspectorWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CaptionsView.bg)
        .ignoresSafeArea(.container, edges: .top)
        .modifier(
            TranslationPump(
                bridge: coordinator.translation,
                languagePair: coordinator.languagePair
            )
        )
        .onChange(of: coordinator.isRunning) { _, isRunning in
            if isRunning { selectedRecord = nil }
        }
        .animation(.easeOut(duration: 0.22), value: sidebarOpen)
    }
}

struct InspectorResizeHandle: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(CaptionsView.borderSoft)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay(Color.clear.frame(width: 10).contentShape(Rectangle()))
            .onHover { isInside in
                if isInside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = base }
                        width = min(maxWidth, max(minWidth, base - value.translation.width))
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}
