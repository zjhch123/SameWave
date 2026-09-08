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
    case simplifiedChinese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }

    /// Presentation only. Prompts use the stable English language name above.
    var localizedLabel: String {
        switch self {
        case .english: String(localized: "English")
        case .simplifiedChinese: String(localized: "Simplified Chinese")
        }
    }

    var localeID: String {
        switch self {
        case .english: "en-US"
        case .simplifiedChinese: "zh-CN"
        }
    }

    var translationIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }
}

enum MeetingLanguagePair: String, Codable, Sendable {
    case englishToEnglish
    case englishToSimplifiedChinese = "english"
    case simplifiedChineseToEnglish
    case simplifiedChineseToSimplifiedChinese = "chinese"

    init(source: MeetingLanguage, target: MeetingLanguage) {
        self = switch (source, target) {
        case (.english, .english): .englishToEnglish
        case (.english, .simplifiedChinese): .englishToSimplifiedChinese
        case (.simplifiedChinese, .english): .simplifiedChineseToEnglish
        case (.simplifiedChinese, .simplifiedChinese): .simplifiedChineseToSimplifiedChinese
        }
    }

    var source: MeetingLanguage {
        switch self {
        case .englishToEnglish, .englishToSimplifiedChinese: .english
        case .simplifiedChineseToEnglish, .simplifiedChineseToSimplifiedChinese: .simplifiedChinese
        }
    }

    var target: MeetingLanguage {
        switch self {
        case .englishToEnglish, .simplifiedChineseToEnglish: .english
        case .englishToSimplifiedChinese, .simplifiedChineseToSimplifiedChinese: .simplifiedChinese
        }
    }

    var needsTranslation: Bool { source != target }
}

enum MeetingStatus: String, Codable, Sendable {
    case draft
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
    var translatedGeneration = 0
    var requestedSource = ""
    var startedAt = Date()
    var priorContext: [String] = []

    var sourceText: String {
        (committedSource + (interimSource.isEmpty ? [] : [interimSource]))
            .joined(separator: " ")
            .trimmed
    }
}
