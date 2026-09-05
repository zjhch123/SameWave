import CryptoKit
import Foundation
import Speech

@available(macOS 26.0, *)
actor CustomSpeechLanguageModel {
    static let shared = CustomSpeechLanguageModel()

    private var preparedConfigurations: [String: SFSpeechLanguageModel.Configuration] = [:]

    func configuration(
        locale: Locale,
        phrases: [String]
    ) async throws -> SFSpeechLanguageModel.Configuration {
        let fingerprint = Self.fingerprint(locale: locale, phrases: phrases)
        if let configuration = preparedConfigurations[fingerprint] {
            return configuration
        }

        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelDirectory = applicationSupport
            .appending(path: "SameWave/SpeechLanguageModel/\(fingerprint)",
                       directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )

        let trainingDataURL = modelDirectory.appending(path: "training-data.bin")
        let languageModelURL = modelDirectory.appending(path: "language-model.bin")
        let vocabularyURL = modelDirectory.appending(path: "vocabulary.bin")

        if !fileManager.fileExists(atPath: trainingDataURL.path) {
            let trainingData = SFCustomLanguageModelData(
                locale: locale,
                identifier: "com.plus.samewave.terms",
                version: fingerprint
            )
            for phrase in phrases {
                trainingData.insert(
                    phraseCount: .init(phrase: phrase, count: 1)
                )
            }
            try await trainingData.export(to: trainingDataURL)
        }

        let configuration = SFSpeechLanguageModel.Configuration(
            languageModel: languageModelURL,
            vocabulary: vocabularyURL
        )
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(
            for: trainingDataURL,
            configuration: configuration,
            ignoresCache: false
        )
        preparedConfigurations[fingerprint] = configuration
        return configuration
    }

    private static func fingerprint(locale: Locale, phrases: [String]) -> String {
        let source = ([locale.identifier(.bcp47)] + phrases).joined(separator: "\u{0}")
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
