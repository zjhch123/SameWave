import Foundation
import XCTest
@testable import SameWave

@MainActor
final class VocabularyGeneratorTests: XCTestCase {
    func testPromptRequiresNamedEntitiesAndRejectsGenericTechnicalTerms() {
        let prompt = VocabularyGenerator.systemPrompt

        XCTAssertTrue(prompt.contains("Named-entity gate"))
        XCTAssertTrue(prompt.contains("Speech-recognition value gate"))
        XCTAssertTrue(prompt.contains("generic technical or business concepts"))
        XCTAssertTrue(prompt.contains("Heading styles, initial capitals, ALL CAPS"))
        XCTAssertTrue(prompt.contains("If uncertain whether both gates are met, omit the candidate"))
        for example in ["SharePoint", "OneDrive for Business", "Primary", "ingestion", "sharding", "metadata"] {
            XCTAssertTrue(prompt.contains(example))
        }
    }

    func testReviewCandidatesOnlyContainPhrasesNewToCurrentDraft() {
        let candidates = SpeechVocabularySettings.newPhrases(
            from: ["xpay", " M365 Copilot ", "m365 copilot", "SwiftData"],
            excluding: ["XPay", "Existing Draft Phrase"]
        )

        XCTAssertEqual(candidates, ["M365 Copilot", "SwiftData"])
    }

    func testGeneratorDeliversEachNormalizedSuccessBeforeNextRequest() async throws {
        let provider = VocabularyProviderStub(responses: [
            .content(#"{"phrases":[" XPay ","xpay"]}"#),
            .content(#"{"phrases":["M365 Copilot"]}"#),
        ])
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "private-name.md",
                                     content: String(repeating: "a", count: 20_001))
        ])
        var events: [String] = []
        var successes: [[String]] = []
        try await VocabularyGenerator(provider: provider).generate(
            batches: batches, totalBatchCount: batches.count
        ) { event in
            switch event {
            case .attempt(let attempt):
                events.append("start \(attempt.batchNumber)")
            case .succeeded(let number, let phrases):
                events.append("success \(number)")
                successes.append(phrases)
            case .failed:
                XCTFail("Unexpected failure")
            }
        }
        XCTAssertEqual(events, ["start 1", "success 1", "start 2", "success 2"])
        XCTAssertEqual(successes, [["XPay"], ["M365 Copilot"]])
        let bodies = await provider.requestBodies()
        XCTAssertFalse(bodies.joined().contains("private-name.md"))
    }

    func testGeneratorRecordsInvalidPhraseContentAfterTwoRetries() async throws {
        let provider = VocabularyProviderStub(responses: Array(
            repeating: .content(#"{"phrases":["first\nsecond"]}"#), count: 3
        ))
        var failures: [Int] = []
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "test.md", content: "content")
        ])
        try await VocabularyGenerator(provider: provider).generate(batches: batches, totalBatchCount: 1) {
            if case .failed(let number, let message) = $0 {
                failures.append(number)
                XCTAssertTrue(message.contains("JSON Schema"))
            }
            if case .succeeded = $0 { XCTFail("Invalid result must not be accepted") }
        }
        XCTAssertEqual(failures, [1])
        let count = await provider.requestCount()
        XCTAssertEqual(count, 3)
    }

    func testGeneratorRetriesTwiceAndPublishesCurrentAttempt() async throws {
        let provider = VocabularyProviderStub(responses: [
            .failure(.network("temporary")), .failure(.server(503)),
            .content(#"{"phrases":["XPay"]}"#),
        ])
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "test.md", content: "XPay")
        ])
        var attempts: [VocabularyAttempt] = []
        var phrases: [String] = []
        try await VocabularyGenerator(provider: provider).generate(batches: batches, totalBatchCount: 1) {
            if case .attempt(let attempt) = $0 { attempts.append(attempt) }
            if case .succeeded(_, let result) = $0 { phrases = result }
        }
        XCTAssertEqual(phrases, ["XPay"])
        XCTAssertEqual(attempts, [
            VocabularyAttempt(batchNumber: 1, number: 1),
            VocabularyAttempt(batchNumber: 1, number: 2),
            VocabularyAttempt(batchNumber: 1, number: 3)
        ])
    }

    func testGeneratorSkipsFailedBatchAndContinuesSerially() async throws {
        let provider = VocabularyProviderStub(responses: [
            .content(#"{"phrases":["XPay"]}"#),
            .failure(.rateLimited), .failure(.rateLimited), .failure(.rateLimited),
            .content(#"{"phrases":["M365 Copilot"]}"#),
        ])
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "test.md", content: String(repeating: "a", count: 41_000))
        ])
        var events: [String] = []
        try await VocabularyGenerator(provider: provider).generate(batches: batches, totalBatchCount: 3) {
            switch $0 {
            case .attempt(let attempt):
                events.append("start \(attempt.batchNumber).\(attempt.number)")
            case .succeeded(let number, _): events.append("success \(number)")
            case .failed(let number, _): events.append("failure \(number)")
            }
        }
        XCTAssertEqual(events, [
            "start 1.1", "success 1", "start 2.1", "start 2.2", "start 2.3",
            "failure 2", "start 3.1", "success 3"
        ])
    }

    func testBatchCombinesDocumentContentInOrderWithoutFileNames() throws {
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "secret.md", content: "# Notes\nUse XPay."),
            VocabularySourceDocument(fileName: "private.md", content: "Use SwiftData.")
        ])
        XCTAssertEqual(batches, [
            VocabularyBatch(number: 1, content: """
            [Document 1, fragment 1/1]
            # Notes
            Use XPay.

            ---

            [Document 2, fragment 1/1]
            Use SwiftData.
            """)
        ])
    }

    func testUnicodeBatchingPreservesAllCharactersInRequestContent() throws {
        let text = String(repeating: "中文👨‍👩‍👧‍👦é", count: 12_000)
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "unicode.md", content: text)
        ])
        XCTAssertTrue(batches.allSatisfy { $0.content.count <= 20_000 })
        XCTAssertEqual(batches.count, 3)
        let fragments = try batches.enumerated().map { index, batch in
            let parts = batch.content.split(separator: "\n", maxSplits: 1)
            XCTAssertEqual(parts.first.map(String.init), "[Document 1, fragment \(index + 1)/3]")
            return String(try XCTUnwrap(parts.last))
        }
        XCTAssertEqual(fragments.joined(), text)
    }

    func testBatchingSplitsOversizedParagraphWithoutLosingContent() throws {
        let content = String(
            repeating: "a",
            count: VocabularyGenerator.fragmentCharacterLimit * 2 + 5_000
        )

        let batches = try VocabularyGenerator.makeBatches(
            from: [VocabularySourceDocument(fileName: "test.md", content: content)]
        )

        XCTAssertEqual(batches.count, 3)
        XCTAssertTrue(batches.allSatisfy { $0.content.count <= VocabularyGenerator.batchCharacterLimit })
        let fragments = try batches.map { batch in
            String(try XCTUnwrap(batch.content.split(separator: "\n", maxSplits: 1).last))
        }
        XCTAssertEqual(fragments.joined(), content)
    }

    func testBatchAndRetryBudgetsMatchRequestContract() {
        XCTAssertEqual(VocabularyGenerator.batchCharacterLimit, 20_000)
        XCTAssertEqual(VocabularyGenerator.fragmentCharacterLimit, 18_000)
        XCTAssertEqual(VocabularyGenerator.maximumRetriesPerBatch, 2)
        XCTAssertEqual(VocabularyGenerator.maximumPhrasesPerBatch, 50)
        XCTAssertEqual(OpenAICompatibleProvider.completionTimeout, 60)
    }

    func testLoaderReadsMultipleMarkdownFiles() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "VocabularyGeneratorTests-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try fileManager.removeItem(at: directory)
        }
        let first = directory.appending(path: "first.md")
        let second = directory.appending(path: "second.markdown")
        try "# XPay".write(to: first, atomically: true, encoding: .utf8)
        try "M365 Copilot".write(to: second, atomically: true, encoding: .utf8)

        let documents = try await VocabularyDocumentLoader.load([first, second])

        XCTAssertEqual(
            documents,
            [
                VocabularySourceDocument(fileName: "first.md", content: "# XPay"),
                VocabularySourceDocument(fileName: "second.markdown", content: "M365 Copilot"),
            ]
        )
    }

    func testLoaderRejectsUnsupportedFileExtensions() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "VocabularyGeneratorTests-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try fileManager.removeItem(at: directory)
        }
        let file = directory.appending(path: "terms.txt")
        try "XPay".write(to: file, atomically: true, encoding: .utf8)

        do {
            _ = try await VocabularyDocumentLoader.load([file])
            XCTFail("Expected unsupported file type to fail")
        } catch let error as VocabularyImportError {
            XCTAssertEqual(error, .unsupportedFile("terms.txt"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoaderAcceptsContentAbovePreviousCharacterLimit() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "VocabularyGeneratorTests-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try fileManager.removeItem(at: directory)
        }
        let file = directory.appending(path: "large.md")
        let content = String(repeating: "a", count: 60_001)
        try content.write(to: file, atomically: true, encoding: .utf8)

        let documents = try await VocabularyDocumentLoader.load([file])

        XCTAssertEqual(documents, [VocabularySourceDocument(fileName: "large.md", content: content)])
    }

    func testLoaderAcceptsMultipleFilesAboveThreeMegabytesInTotal() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "VocabularyGeneratorTests-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try fileManager.removeItem(at: directory)
        }
        let first = directory.appending(path: "first.md")
        let second = directory.appending(path: "second.md")
        let firstContent = String(repeating: "a", count: 2_000_000)
        let secondContent = String(repeating: "b", count: 2_000_000)
        try firstContent.write(to: first, atomically: true, encoding: .utf8)
        try secondContent.write(to: second, atomically: true, encoding: .utf8)

        let documents = try await VocabularyDocumentLoader.load([first, second])

        XCTAssertEqual(
            documents,
            [
                VocabularySourceDocument(fileName: "first.md", content: firstContent),
                VocabularySourceDocument(fileName: "second.md", content: secondContent),
            ]
        )
    }

    func testLoaderRejectsSingleFileAboveThreeMegabytes() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "VocabularyGeneratorTests-\(UUID().uuidString)",
                       directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try fileManager.removeItem(at: directory)
        }
        let file = directory.appending(path: "too-large.md")
        try String(
            repeating: "a",
            count: VocabularyDocumentLoader.maximumFileBytes + 1
        ).write(to: file, atomically: true, encoding: .utf8)

        do {
            _ = try await VocabularyDocumentLoader.load([file])
            XCTFail("Expected an oversized file to fail")
        } catch let error as VocabularyImportError {
            XCTAssertEqual(error, .fileTooLarge("too-large.md"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoaderRejectsSelectionAboveThirtyMegabytes() throws {
        XCTAssertNoThrow(
            try VocabularyDocumentLoader.validateFileSize(
                VocabularyDocumentLoader.maximumFileBytes,
                selectedBytes: VocabularyDocumentLoader.maximumSelectionBytes
                    - VocabularyDocumentLoader.maximumFileBytes,
                fileName: "last-allowed.md"
            )
        )

        XCTAssertThrowsError(
            try VocabularyDocumentLoader.validateFileSize(
                1,
                selectedBytes: VocabularyDocumentLoader.maximumSelectionBytes,
                fileName: "over-total.md"
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .selectionTooLarge)
        }
    }
}

private enum VocabularyProviderStubResponse: Sendable {
    case content(String)
    case failure(LLMError)
}

private actor VocabularyProviderStub: LLMProvider {
    private let responses: [VocabularyProviderStubResponse]
    private var index = 0
    private var requests = 0
    private var bodies: [String] = []

    init(responses: [VocabularyProviderStubResponse]) {
        self.responses = responses
    }

    func complete(system: String, user: String,
                  schema: LLMResponseSchema) async throws -> String {
        requests += 1
        bodies.append(user)
        guard index < responses.count else { throw LLMError.badResponse }
        defer { index += 1 }
        switch responses[index] {
        case .content(let content):
            return content
        case .failure(let error):
            throw error
        }
    }

    func requestBodies() -> [String] { bodies }

    func requestCount() -> Int {
        requests
    }
}
