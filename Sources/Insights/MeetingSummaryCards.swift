import SwiftUI

/// Named parts are always expanded and share their parent's version selection.
struct MeetingSummaryCards: View {
    let summary: MeetingSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((summary ?? .empty).parts.enumerated()), id: \.element.id) { index, part in
                VStack(alignment: .leading, spacing: 8) {
                    Label(part.title, systemImage: part.symbol)
                        .font(.system(size: 12, weight: .semibold))
                    if summary == nil {
                        Text("No content yet.").foregroundStyle(CaptionsView.muted)
                    } else if part.items.isEmpty {
                        Text(part.emptyMessage).foregroundStyle(CaptionsView.muted)
                    } else {
                        ForEach(Array(part.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•").foregroundStyle(CaptionsView.muted)
                                Text(item).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(CaptionsView.fg)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(InsightCardPalette.fill(index), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain).accessibilityLabel(part.title)
            }
        }
    }
}

extension InsightCardPalette {
    @MainActor static func fill(_ slot: Int) -> Color {
        switch slot % 4 {
        case 0: Color(red: 0.940, green: 0.967, blue: 0.993)
        case 1: Color(red: 0.961, green: 0.949, blue: 0.988)
        case 2: Color(red: 0.930, green: 0.969, blue: 0.949)
        default: CaptionsView.surface
        }
    }
}
