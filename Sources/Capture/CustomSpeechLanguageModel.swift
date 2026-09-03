import Foundation
import Speech

@available(macOS 26.0, *)
actor CustomSpeechLanguageModel {
    static let shared = CustomSpeechLanguageModel()

    private static let modelVersion = "1"
    private var preparedConfiguration: SFSpeechLanguageModel.Configuration?

    func configuration(
        locale: Locale,
        phrases: [String]
    ) async throws -> SFSpeechLanguageModel.Configuration {
        if let preparedConfiguration { return preparedConfiguration }

        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelDirectory = applicationSupport
            .appending(path: "MeetingCaptions/SpeechLanguageModel/\(Self.modelVersion)",
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
                identifier: "com.plus.meetingcaptions.terms",
                version: Self.modelVersion
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
        preparedConfiguration = configuration
        return configuration
    }
}
