import Foundation

/// User-editable terminology corrections applied to translated Chinese.
///
/// Apple's local translator is sentence-level NMT and cannot take a domain hint
/// or glossary, so ambiguous terms (e.g. English "power" → 功率 vs 权力) can't be
/// forced at translation time. This post-corrects known mistranslations for the
/// user's meeting domain. Loaded from `glossary.json` (App Support or the project
/// dir) as a { wrong: right } map; fully user-editable, empty is fine.
enum Glossary {
    /// (wrong, right) pairs, longest wrong-key first so longer phrases win.
    private static let entries: [(String, String)] = load()

    static var isEmpty: Bool { entries.isEmpty }

    /// Apply all corrections to a finalized Chinese string.
    static func apply(_ text: String) -> String {
        guard !entries.isEmpty, !text.isEmpty else { return text }
        var out = text
        for (wrong, right) in entries {
            out = out.replacingOccurrences(of: wrong, with: right)
        }
        return out
    }

    private static func load() -> [(String, String)] {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: false) {
            candidates.append(appSupport.appending(path: "MeetingCaptions/glossary.json"))
        }
        candidates.append(URL(fileURLWithPath:
            ("~/Desktop/thoughts/MeetingCaptions/glossary.json" as NSString).expandingTildeInPath))
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath)
            .appending(path: "glossary.json"))

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            // Longest keys first so multi-char terms replace before their substrings.
            return dict.sorted { $0.key.count > $1.key.count }.map { ($0.key, $0.value) }
        }
        return []
    }
}
