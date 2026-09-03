import Foundation

enum Speaker: String, Codable, Hashable, Sendable {
    case remote
    case mine = "me"

    var persistedValue: String { rawValue }

    init(persistedValue: String) {
        guard let value = Self(rawValue: persistedValue) else {
            preconditionFailure("Invalid persisted speaker: \(persistedValue)")
        }
        self = value
    }
}

enum MeetingLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english
    case chinese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: "英文（译中）"
        case .chinese: "中文（不翻译）"
        }
    }

    var shortLabel: String {
        switch self {
        case .english: "英→中"
        case .chinese: "中文"
        }
    }

    var localeID: String {
        switch self {
        case .english: "en-US"
        case .chinese: "zh-CN"
        }
    }

    var translationSource: String? {
        switch self {
        case .english: "en"
        case .chinese: nil
        }
    }

    var needsTranslation: Bool { translationSource != nil }
}

enum MeetingStatus: String, Codable, Sendable {
    case recording
    case paused
    case ended
}

enum MeetingSessionState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case pausing
    case paused
    case stopping

    var hasActiveSession: Bool { self != .idle }
    var acceptsCaptureControls: Bool { self == .recording || self == .paused }
}

enum ContentState: Sendable {
    case open
    case sealed
}

enum TranslationState: Sendable {
    case pending
    case translating
    case done
    case failed
}

struct Section: Identifiable, Equatable, Sendable {
    let id: Int
    let speaker: Speaker
    var contentState: ContentState = .open
    var translationState: TranslationState = .pending
    var committedSource: [String] = []
    var interimSource = ""
    var targetText = ""
    var generation = 0
    var startedAt = Date()
    var priorContext: [String] = []

    var sourceText: String {
        (committedSource + (interimSource.isEmpty ? [] : [interimSource]))
            .joined(separator: " ")
            .trimmed
    }
}
