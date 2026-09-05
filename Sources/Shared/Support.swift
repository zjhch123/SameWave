import Foundation

// Small shared utilities used across the app, so common idioms live in exactly one
// place (no duplicated trim calls, no per-access DateFormatter allocation).

extension String {
    /// Whitespace/newline-trimmed copy — the app's most-repeated one-liner.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True if the string carries real spoken content: at least one letter, digit, or
    /// CJK / kana character. Filters out noise-only recognitions that are just
    /// whitespace or lone punctuation (e.g. "." from ambient noise), which otherwise
    /// litter the transcript and the saved record.
    var hasSpokenContent: Bool {
        unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains($0.value)   // CJK Unified Ideographs
                || (0x3040...0x30FF).contains($0.value)   // Hiragana + Katakana
        }
    }
}

/// Shared, cached date formatters. `DateFormatter` is expensive to build, and these
/// are read per-row on every SwiftUI redraw, so they must be created once — not on
/// each access.
enum DateFormat {
    /// "Jul 7, 2026 at 18:27" — a saved meeting's title.
    static let dayTime: DateFormatter = make("MMM d, yyyy 'at' HH:mm")
    /// "18:27" — a per-line spoken time.
    static let clock: DateFormatter = make("HH:mm")
    /// "20260707-1827" — a filename-safe export stamp.
    static let fileStamp: DateFormatter = make("yyyyMMdd-HHmm")

    private static func make(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = pattern
        return f
    }
}
