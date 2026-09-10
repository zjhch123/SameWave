import XCTest
@testable import SameWave

@MainActor
final class AISettingsControllerTests: XCTestCase {
    func testIncompleteInputPersistsWithoutBlockingOtherPreferences() {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        let controller = AISettingsController(settings: settings)
        controller.providerID = "custom"
        controller.customAPIAddress = "https://example.com/v1"
        controller.customModel = "saved-model"
        for text in ["", " ", "16384x", "16384.5", "16,,384", "1e6", "16383", "2000001",
                     "999999999999999999999999"] {
            controller.contextBudgetText = text
            XCTAssertFalse(controller.isContextBudgetValid, text)
            XCTAssertFalse(settings.isAvailable, text)
            XCTAssertNil(settings.makeProvider(), text)
            let reopened = AISettings(defaults: defaults, initialAPIKey: "test-key")
            XCTAssertEqual(reopened.selectedProviderID, "custom", text)
            XCTAssertEqual(reopened.customAPIAddress, "https://example.com/v1", text)
            XCTAssertEqual(reopened.customModel, "saved-model", text)
            XCTAssertEqual(reopened.contextBudgetText, text)
            XCTAssertNil(reopened.insightContextTokenBudget, text)
        }
        controller.isEnabled = false
        XCTAssertFalse(settings.isEnabled, "Invalid input must not block immediate shutdown")
    }

    func testEditingWhileDisabledPersistsAndValidInputRestoresAvailability() {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        let controller = AISettingsController(settings: settings)
        controller.isEnabled = false
        controller.providerID = "custom"
        controller.customAPIAddress = "https://example.com/v1"
        controller.customModel = "saved-model"
        for (text, expected) in [("16,384", 16_384), ("2000000", 2_000_000), (" 64,000 ", 64_000)] {
            controller.contextBudgetText = text
            XCTAssertTrue(controller.isContextBudgetValid)
            XCTAssertFalse(settings.isAvailable)
            let reopened = AISettings(defaults: defaults, initialAPIKey: "test-key")
            XCTAssertEqual(reopened.customModel, "saved-model")
            XCTAssertEqual(reopened.insightContextTokenBudget, expected)
            XCTAssertFalse(reopened.isEnabled)
        }
        controller.isEnabled = true
        XCTAssertTrue(settings.isAvailable)
        for address in ["", "ftp://example.com", "https://"] {
            controller.customAPIAddress = address
            XCTAssertFalse(settings.isAvailable)
            XCTAssertEqual(AISettings(defaults: defaults).customAPIAddress, address)
        }
        controller.customAPIAddress = "http://localhost:8080/v1"
        XCTAssertTrue(settings.isAvailable)
        controller.customModel = ""
        XCTAssertFalse(settings.isAvailable)
        XCTAssertEqual(AISettings(defaults: defaults).customModel, "")
    }

    func testAPIKeyAutosaveReportsFailuresAndRetriesWithoutTouchingRealKeychain() {
        let defaults = Phase2Fixture.defaults(self)
        var savedKey = "previous-key"
        var failWrite = true
        let settings = AISettings(defaults: defaults, initialAPIKey: savedKey, storeAPIKey: { value in
            if failWrite { throw KeychainStore.StorageError(status: -25293) }
            savedKey = value
        })
        let controller = AISettingsController(settings: settings)
        controller.apiKey = " new-key "
        XCTAssertEqual(savedKey, "previous-key")
        XCTAssertNotNil(controller.apiKeyStorageError)
        XCTAssertFalse(settings.isAvailable)
        XCTAssertFalse(controller.canFetchModels)
        XCTAssertEqual(controller.apiKey, " new-key ")
        failWrite = false
        controller.retrySavingAPIKey()
        XCTAssertEqual(savedKey, "new-key")
        XCTAssertNil(controller.apiKeyStorageError)
        XCTAssertTrue(settings.isAvailable)
        failWrite = true
        controller.apiKey = ""
        XCTAssertEqual(savedKey, "new-key")
        XCTAssertNotNil(controller.apiKeyStorageError)
        XCTAssertFalse(settings.isAvailable)
        failWrite = false
        controller.retrySavingAPIKey()
        XCTAssertEqual(savedKey, "")
        XCTAssertNil(controller.apiKeyStorageError)
        XCTAssertFalse(settings.isAvailable)
        XCTAssertNil(defaults.string(forKey: "insight.apiKey"))
    }

    func testDisablingBeforeScheduledChecksStartMakesNoRequests() async throws {
        let controller = makeController()
        let provider = HeldSettingsProvider()
        let models = HeldModelList()
        addTeardownBlock { await provider.releaseAll(); await models.releaseAll() }
        controller.testConnection(using: provider)
        controller.fetchModels { await models.load() }
        controller.isEnabled = false
        try await Task.sleep(for: .milliseconds(30))
        let tests = await provider.count
        let lists = await models.count
        XCTAssertEqual(tests, 0)
        XCTAssertEqual(lists, 0)
        XCTAssertEqual(controller.testState, .idle)
        XCTAssertEqual(controller.modelDiscoveryState, .idle)
    }

    func testConnectionChecksUseCurrentSettingsAndRejectRepliesAfterEdits() async throws {
        let settings = AISettings(defaults: Phase2Fixture.defaults(self), initialAPIKey: "test-key")
        let controller = AISettingsController(settings: settings)
        let provider = HeldSettingsProvider()
        addTeardownBlock { await provider.releaseAll() }
        controller.customModel = "first-model"
        XCTAssertEqual(settings.customModel, "first-model")
        controller.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await provider.complete(0)
        try await Phase2Fixture.waitUntil { controller.testState == .ok }
        controller.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        controller.customModel = "second-model"
        await provider.complete(1)
        await Task.yield()
        XCTAssertEqual(controller.testState, .idle)
        XCTAssertEqual(settings.customModel, "second-model")
    }

    func testMasterSwitchCancelsAndBlocksRequestsWithoutLosingEdits() async throws {
        let controller = makeController()
        let provider = HeldSettingsProvider()
        let models = HeldModelList()
        addTeardownBlock { await provider.releaseAll(); await models.releaseAll() }
        controller.testConnection(using: provider)
        controller.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil {
            let tests = await provider.count
            let lists = await models.count
            return tests == 1 && lists == 1
        }
        controller.isEnabled = false
        XCTAssertEqual(controller.testState, .idle)
        XCTAssertEqual(controller.modelDiscoveryState, .idle)
        XCTAssertFalse(controller.canFetchModels)
        controller.testConnection(using: provider)
        controller.fetchModels { await models.load() }
        await provider.complete(0)
        await models.complete(0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.testState, .idle)
        XCTAssertTrue(controller.availableModels.isEmpty)
        XCTAssertEqual(controller.customModel, "initial-model")
        let tests = await provider.count
        let lists = await models.count
        XCTAssertEqual(tests, 1)
        XCTAssertEqual(lists, 1)
        controller.isEnabled = true
        XCTAssertTrue(controller.canFetchModels)
        controller.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await provider.complete(1)
        try await Phase2Fixture.waitUntil { controller.testState == .ok }
    }

    func testChangedConnectionRejectsLateSuccessAndAllowsNewTest() async throws {
        let controller = makeController()
        let provider = HeldSettingsProvider()
        addTeardownBlock { await provider.releaseAll() }
        controller.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        controller.customAPIAddress = "https://new.example.com/v1"
        XCTAssertEqual(controller.testState, .idle)
        controller.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await provider.complete(0)
        await Task.yield()
        XCTAssertEqual(controller.testState, .testing)
        await provider.complete(1)
        try await Phase2Fixture.waitUntil { controller.testState == .ok }
        controller.customModel = "another-model"
        XCTAssertEqual(controller.testState, .idle)
    }

    func testInvalidConnectionResponseRemainsVisible() async throws {
        let controller = makeController()
        let provider = HeldSettingsProvider()
        addTeardownBlock { await provider.releaseAll() }
        controller.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await provider.complete(0, raw: #"{"status":{"ok":true},"values":[9]}"#)
        try await Phase2Fixture.waitUntil { controller.testState != .testing }
        XCTAssertEqual(controller.testState, .failed(LLMError.schemaViolation.localizedDescription))
    }

    func testDismissalCancelsChecksClearsLoadingAndPreservesPreferences() async throws {
        let controller = makeController()
        let provider = HeldSettingsProvider()
        let models = HeldModelList()
        addTeardownBlock { await provider.releaseAll(); await models.releaseAll() }
        controller.testConnection(using: provider)
        controller.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil {
            let testCount = await provider.count
            let modelCount = await models.count
            return testCount == 1 && modelCount == 1
        }
        controller.cancelRequests()
        XCTAssertEqual(controller.testState, .idle)
        XCTAssertEqual(controller.modelDiscoveryState, .idle)
        XCTAssertTrue(controller.canFetchModels)
        XCTAssertEqual(controller.customModel, "initial-model")
        await provider.complete(0)
        await models.complete(0)
        await Task.yield()
        XCTAssertEqual(controller.testState, .idle)
        XCTAssertTrue(controller.availableModels.isEmpty)
        XCTAssertEqual(controller.customModel, "initial-model")
        controller.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil { await models.count == 2 }
        await models.complete(1)
        try await Phase2Fixture.waitUntil { controller.modelDiscoveryState == .loaded(1) }
        XCTAssertEqual(controller.customModel, "discovered-model")
    }

    func testModelDiscoveryDoesNotReplaceManualModelEdit() async throws {
        let controller = makeController()
        let models = HeldModelList()
        addTeardownBlock { await models.releaseAll() }
        controller.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil { await models.count == 1 }
        controller.customModel = "manually-entered-model"
        await models.complete(0)
        try await Phase2Fixture.waitUntil { controller.modelDiscoveryState == .loaded(1) }
        XCTAssertEqual(controller.customModel, "manually-entered-model")
        controller.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil { await models.count == 2 }
        controller.apiKey = "changed-test-key"
        await models.complete(1)
        await Task.yield()
        XCTAssertEqual(controller.modelDiscoveryState, .idle)
        XCTAssertTrue(controller.availableModels.isEmpty)
    }

    private func makeController() -> AISettingsController {
        let controller = AISettingsController(settings: AISettings(defaults: Phase2Fixture.defaults(self)))
        controller.providerID = "custom"
        controller.apiKey = "test-key"
        controller.customAPIAddress = "https://example.com/v1"
        controller.customModel = "initial-model"
        return controller
    }
}

private actor HeldSettingsProvider: LLMProvider {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]

    func complete(system: String, user: String, schema: LLMResponseSchema) async throws -> String {
        let index = count
        count += 1
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func complete(_ index: Int, raw: String = #"{"status":{"ok":true},"values":[1,2]}"#) {
        pending.removeValue(forKey: index)?.resume(returning: raw)
    }

    func releaseAll() {
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
        pending.removeAll()
    }
}

private actor HeldModelList {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<[LLMModel], Never>] = [:]

    func load() async -> [LLMModel] {
        let index = count
        count += 1
        return await withCheckedContinuation { pending[index] = $0 }
    }

    func complete(_ index: Int) {
        pending.removeValue(forKey: index)?.resume(returning: [LLMModel(id: "discovered-model", ownedBy: nil)])
    }

    func releaseAll() {
        for continuation in pending.values { continuation.resume(returning: []) }
        pending.removeAll()
    }
}
