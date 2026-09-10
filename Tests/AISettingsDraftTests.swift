import XCTest
@testable import SameWave

@MainActor
final class AISettingsDraftTests: XCTestCase {
    func testVisibleInvalidContextPreventsEveryConnectionPreferenceFromSaving() {
        let settings = AISettings(defaults: Phase2Fixture.defaults(self), initialAPIKey: "test-key")
        let draft = AISettingsDraft(settings: settings)
        draft.providerID = "custom"
        draft.customAPIAddress = "https://example.com/v1"
        draft.customModel = "pending-model"
        for text in ["", " ", "16384x", "16384.5", "16,,384", "1e6", "16383", "2000001",
                     "999999999999999999999999"] {
            draft.contextBudgetText = text
            XCTAssertTrue(draft.isDirty, text)
            XCTAssertFalse(draft.canSave, text)
            draft.save()
            XCTAssertEqual(settings.selectedProviderID, LLMProviderConfig.qwen.id, text)
            XCTAssertEqual(settings.customAPIAddress, "", text)
            XCTAssertEqual(settings.customModel, "", text)
            XCTAssertEqual(settings.insightContextTokenBudget, AISettings.defaultContextTokenBudget, text)
            XCTAssertEqual(draft.contextBudgetText, text)
        }
        draft.isEnabled = false
        XCTAssertFalse(settings.isEnabled, "Invalid connection input must not block immediate shutdown")
        draft.revert()
        XCTAssertFalse(draft.isDirty)
        XCTAssertFalse(settings.isEnabled)
    }

    func testSavingConnectionWhileDisabledCommitsOnlyExplicitValidDraft() {
        let defaults = Phase2Fixture.defaults(self)
        let settings = AISettings(defaults: defaults, initialAPIKey: "test-key")
        let draft = AISettingsDraft(settings: settings)
        draft.isEnabled = false
        XCTAssertFalse(draft.isDirty, "The immediate switch never needs a connection save")
        draft.providerID = "custom"
        draft.customAPIAddress = "https://example.com/v1"
        draft.customModel = "saved-model"
        for (text, expected) in [("16,384", 16_384), ("2000000", 2_000_000), (" 64,000 ", 64_000)] {
            draft.contextBudgetText = text
            XCTAssertTrue(draft.canSave)
            draft.save()
            XCTAssertFalse(draft.isDirty)
            XCTAssertFalse(draft.canSave)
            XCTAssertFalse(settings.isEnabled)
            let reopened = AISettings(defaults: defaults, initialAPIKey: "test-key")
            XCTAssertEqual(reopened.selectedProviderID, "custom")
            XCTAssertEqual(reopened.customAPIAddress, "https://example.com/v1")
            XCTAssertEqual(reopened.customModel, "saved-model")
            XCTAssertEqual(reopened.insightContextTokenBudget, expected)
        }
    }

    func testDisablingBeforeScheduledChecksStartMakesNoRequests() async throws {
        let draft = makeDraft()
        let provider = HeldSettingsProvider()
        let models = HeldModelList()
        addTeardownBlock { await provider.releaseAll(); await models.releaseAll() }
        draft.testConnection(using: provider)
        draft.fetchModels { await models.load() }
        draft.isEnabled = false
        try await Task.sleep(for: .milliseconds(30))
        let tests = await provider.count
        let lists = await models.count
        XCTAssertEqual(tests, 0)
        XCTAssertEqual(lists, 0)
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertEqual(draft.modelDiscoveryState, .idle)
    }

    func testConnectionChecksNeverSaveAndLocalActionsRejectLateReplies() async throws {
        let settings = AISettings(defaults: Phase2Fixture.defaults(self), initialAPIKey: "test-key")
        let draft = AISettingsDraft(settings: settings)
        let provider = HeldSettingsProvider()
        addTeardownBlock { await provider.releaseAll() }
        draft.customModel = "first-model"
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await provider.complete(0)
        try await Phase2Fixture.waitUntil { draft.testState == .ok }
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(settings.customModel, "")
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        draft.save()
        await provider.complete(1)
        await Task.yield()
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertEqual(settings.customModel, "first-model")
        draft.customModel = "second-model"
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 3 }
        draft.revert()
        await provider.complete(2)
        await Task.yield()
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertEqual(draft.customModel, "first-model")
    }

    func testMasterSwitchCancelsAndBlocksDraftRequestsWithoutLosingEdits() async throws {
        let draft = makeDraft()
        let provider = HeldSettingsProvider()
        let models = HeldModelList()
        addTeardownBlock { await provider.releaseAll(); await models.releaseAll() }
        draft.testConnection(using: provider)
        draft.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil {
            let tests = await provider.count
            let lists = await models.count
            return tests == 1 && lists == 1
        }
        draft.isEnabled = false
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertEqual(draft.modelDiscoveryState, .idle)
        XCTAssertFalse(draft.canFetchModels)
        draft.testConnection(using: provider)
        draft.fetchModels { await models.load() }
        await provider.complete(0)
        await models.complete(0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertTrue(draft.availableModels.isEmpty)
        XCTAssertEqual(draft.customModel, "initial-model")
        let tests = await provider.count
        let lists = await models.count
        XCTAssertEqual(tests, 1)
        XCTAssertEqual(lists, 1)
        draft.isEnabled = true
        XCTAssertTrue(draft.canFetchModels)
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await provider.complete(1)
        try await Phase2Fixture.waitUntil { draft.testState == .ok }
    }

    func testChangedConnectionRejectsLateSuccessAndAllowsNewTest() async throws {
        let draft = makeDraft()
        let provider = HeldSettingsProvider()
        addTeardownBlock { await provider.releaseAll() }
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        draft.customAPIAddress = "https://new.example.com/v1"
        XCTAssertEqual(draft.testState, .idle)
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 2 }
        await provider.complete(0)
        await Task.yield()
        XCTAssertEqual(draft.testState, .testing)
        await provider.complete(1)
        try await Phase2Fixture.waitUntil { draft.testState == .ok }
        draft.customModel = "another-model"
        XCTAssertEqual(draft.testState, .idle)
    }

    func testInvalidConnectionResponseRemainsVisible() async throws {
        let draft = makeDraft()
        let provider = HeldSettingsProvider()
        addTeardownBlock { await provider.releaseAll() }
        draft.testConnection(using: provider)
        try await Phase2Fixture.waitUntil { await provider.count == 1 }
        await provider.complete(0, raw: #"{"status":{"ok":true},"values":[9]}"#)
        try await Phase2Fixture.waitUntil { draft.testState != .testing }
        XCTAssertEqual(draft.testState, .failed(LLMError.schemaViolation.localizedDescription))
    }

    func testDismissalCancelsChecksClearsLoadingAndPreservesDraft() async throws {
        let draft = makeDraft()
        let provider = HeldSettingsProvider()
        let models = HeldModelList()
        addTeardownBlock { await provider.releaseAll(); await models.releaseAll() }
        draft.testConnection(using: provider)
        draft.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil {
            let testCount = await provider.count
            let modelCount = await models.count
            return testCount == 1 && modelCount == 1
        }
        draft.cancelRequests()
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertEqual(draft.modelDiscoveryState, .idle)
        XCTAssertTrue(draft.canFetchModels)
        XCTAssertEqual(draft.customModel, "initial-model")
        await provider.complete(0)
        await models.complete(0)
        await Task.yield()
        XCTAssertEqual(draft.testState, .idle)
        XCTAssertTrue(draft.availableModels.isEmpty)
        XCTAssertEqual(draft.customModel, "initial-model")
        draft.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil { await models.count == 2 }
        await models.complete(1)
        try await Phase2Fixture.waitUntil { draft.modelDiscoveryState == .loaded(1) }
        XCTAssertEqual(draft.customModel, "discovered-model")
    }

    func testModelDiscoveryDoesNotReplaceManualModelEdit() async throws {
        let draft = makeDraft()
        let models = HeldModelList()
        addTeardownBlock { await models.releaseAll() }
        draft.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil { await models.count == 1 }
        draft.customModel = "manually-entered-model"
        await models.complete(0)
        try await Phase2Fixture.waitUntil { draft.modelDiscoveryState == .loaded(1) }
        XCTAssertEqual(draft.customModel, "manually-entered-model")
        draft.fetchModels { await models.load() }
        try await Phase2Fixture.waitUntil { await models.count == 2 }
        draft.apiKey = "changed-test-key"
        await models.complete(1)
        await Task.yield()
        XCTAssertEqual(draft.modelDiscoveryState, .idle)
        XCTAssertTrue(draft.availableModels.isEmpty)
    }

    private func makeDraft() -> AISettingsDraft {
        let draft = AISettingsDraft(settings: AISettings(defaults: Phase2Fixture.defaults(self)))
        draft.providerID = "custom"
        draft.apiKey = "test-key"
        draft.customAPIAddress = "https://example.com/v1"
        draft.customModel = "initial-model"
        return draft
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
