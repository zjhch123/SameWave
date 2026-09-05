import Foundation
import XCTest
@testable import 同频

@MainActor
final class VocabularyGeneratorTests: XCTestCase {
    func testPromptRequiresNamedEntitiesAndRejectsGenericTechnicalTerms() {
        let prompt = VocabularyGenerator.systemPrompt

        XCTAssertTrue(prompt.contains("命名实体门槛"))
        XCTAssertTrue(prompt.contains("语音识别价值门槛"))
        XCTAssertTrue(prompt.contains("通用技术或业务概念"))
        XCTAssertTrue(prompt.contains("标题格式、首字母大写、全大写"))
        XCTAssertTrue(prompt.contains("不确定是否同时满足两个门槛时一律省略"))
        XCTAssertTrue(prompt.contains("SharePoint、OneDrive for Business"))
        XCTAssertTrue(prompt.contains("Primary、ingestion、sharding、metadata"))
    }

    func testReviewCandidatesOnlyContainPhrasesNewToCurrentDraft() {
        let candidates = VocabularyCandidateReview.newPhrases(
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
        var timings: [VocabularyAttempt] = []
        try await VocabularyGenerator(provider: provider).generate(
            batches: batches, totalBatchCount: batches.count
        ) { event in
            switch event {
            case .attempt(let attempt):
                if attempt.outcome == .running {
                    events.append("start \(attempt.batchNumber)")
                } else {
                    timings.append(attempt)
                }
            case .succeeded(let number, let phrases):
                events.append("success \(number)")
                successes.append(phrases)
            case .failed:
                XCTFail("Unexpected failure")
            }
        }
        XCTAssertEqual(events, ["start 1", "success 1", "start 2", "success 2"])
        XCTAssertEqual(successes, [["XPay"], ["M365 Copilot"]])
        XCTAssertEqual(timings.count, 2)
        XCTAssertTrue(timings.allSatisfy { ($0.duration ?? -1) >= 0 })
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

    func testGeneratorRetriesTwiceAndRecordsEveryAttempt() async throws {
        let provider = VocabularyProviderStub(responses: [
            .failure(.network("temporary")), .failure(.server(503)),
            .content(#"{"phrases":["XPay"]}"#),
        ])
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "test.md", content: "XPay")
        ])
        var timings: [VocabularyAttempt] = []
        var phrases: [String] = []
        try await VocabularyGenerator(provider: provider).generate(batches: batches, totalBatchCount: 1) {
            if case .attempt(let timing) = $0, timing.duration != nil { timings.append(timing) }
            if case .succeeded(_, let result) = $0 { phrases = result }
        }
        XCTAssertEqual(phrases, ["XPay"])
        XCTAssertEqual(timings.map(\.number), [1, 2, 3])
        XCTAssertEqual(timings.map(\.outcome), [
            .failed(LLMError.network("temporary").localizedDescription),
            .failed(LLMError.server(503).localizedDescription), .succeeded
        ])
        XCTAssertTrue(timings.allSatisfy { ($0.duration ?? -1) >= 0 })
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
            case .attempt(let timing) where timing.outcome == .running:
                events.append("start \(timing.batchNumber).\(timing.number)")
            case .succeeded(let number, _): events.append("success \(number)")
            case .failed(let number, _): events.append("failure \(number)")
            default: break
            }
        }
        XCTAssertEqual(events, [
            "start 1.1", "success 1", "start 2.1", "start 2.2", "start 2.3",
            "failure 2", "start 3.1", "success 3"
        ])
    }

    func testSourceExcerptsAreLocalVerbatimAndNeverInvented() throws {
        let text = "# Notes\nUse XPay with SwiftData."
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "secret.md", content: text)
        ])
        XCTAssertEqual(batches[0].excerpts(for: "xpay"), [
            VocabularySourceExcerpt(fileName: "secret.md", text: text)
        ])
        XCTAssertTrue(batches[0].excerpts(for: "InventedProduct").isEmpty)
        XCTAssertFalse(batches[0].content.contains("secret.md"))
    }

    func testUnicodeBatchingPreservesAllCharactersAndLocalSources() throws {
        let text = String(repeating: "中文👨‍👩‍👧‍👦é", count: 12_000)
        let batches = try VocabularyGenerator.makeBatches(from: [
            VocabularySourceDocument(fileName: "unicode.md", content: text)
        ])
        XCTAssertTrue(batches.allSatisfy { $0.content.count <= 20_000 })
        XCTAssertEqual(batches.flatMap(\.sources).map(\.content).joined(), text)
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
        XCTAssertEqual(batches.map(\.content).joined().filter { $0 == "a" }.count, content.count)
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
