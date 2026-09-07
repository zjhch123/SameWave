import Foundation
import XCTest
@testable import SameWave

@MainActor
final class TranslationBridgeTests: XCTestCase {
    func testCoalescesPerSectionAndPreservesCrossSectionOrder() async throws {
        let bridge = TranslationBridge()
        let probe = TranslationProbe()
        enqueue(bridge, section: 1, generation: 1, text: "old")
        enqueue(bridge, section: 2, generation: 1, text: "two")
        enqueue(bridge, section: 1, generation: 2, text: "new")
        let consumer = run(bridge, probe: probe)
        defer { consumer.cancel(); probe.finishAll() }
        try await Phase2Fixture.waitUntil { probe.requests.count == 1 }
        enqueue(bridge, section: 1, generation: 3, text: "third")
        enqueue(bridge, section: 1, generation: 4, text: "fourth")
        XCTAssertEqual(probe.requests[0].source, "new")
        probe.finish(0, text: "one")
        try await Phase2Fixture.waitUntil { probe.requests.count == 2 }
        XCTAssertEqual(probe.requests[1].sectionId, 2)
        probe.finish(1, text: "two")
        try await Phase2Fixture.waitUntil { probe.requests.count == 3 }
        XCTAssertEqual(probe.requests[2].generation, 4)
        probe.finish(2, text: "four")
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
    }

    func testIdleCancellationDoesNotPoisonNextConsumer() async throws {
        let bridge = TranslationBridge()
        let probe = TranslationProbe()
        let first = run(bridge, probe: probe)
        try await Phase2Fixture.waitUntil { probe.preparations == 1 }
        first.cancel()
        await first.value
        bridge.restart()
        let second = run(bridge, probe: probe)
        defer { second.cancel(); probe.finishAll() }
        try await Phase2Fixture.waitUntil { probe.preparations == 2 }
        enqueue(bridge, section: 0, generation: 1, text: "after language change")
        try await Phase2Fixture.waitUntil { probe.requests.count == 1 }
        probe.finish(0, text: "Recovered")
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
    }

    func testPreparationFailureSettlesCurrentAndFutureRequestsUntilRestart() async throws {
        let bridge = TranslationBridge()
        var failures: [Int] = []
        bridge.onFailed = { failures.append($0.sectionId) }
        enqueue(bridge, section: 0, generation: 1, text: "before failure")
        await bridge.run(prepare: { throw CancellationError() },
                         translate: { _ in XCTFail("Preparation failed"); return "" }, cancel: {})
        enqueue(bridge, section: 1, generation: 1, text: "after failure")
        XCTAssertEqual(failures, [0, 1])
        XCTAssertTrue(bridge.isIdle)
        bridge.restart()
        let probe = TranslationProbe()
        let consumer = run(bridge, probe: probe)
        defer { consumer.cancel(); probe.finishAll() }
        enqueue(bridge, section: 2, generation: 1, text: "retry")
        try await Phase2Fixture.waitUntil { probe.requests.count == 1 }
        probe.finish(0, text: "Success")
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
        XCTAssertEqual(failures, [0, 1])
    }

    func testTimeoutSettlesAllWorkAndDiscardsLateReply() async throws {
        let bridge = TranslationBridge()
        let probe = TranslationProbe()
        var failures: [Int] = []
        var successes: [String] = []
        bridge.onFailed = { failures.append($0.sectionId) }
        bridge.onTranslated = { _, text in successes.append(text) }
        enqueue(bridge, section: 0, generation: 1, text: "blocked")
        enqueue(bridge, section: 1, generation: 1, text: "waiting")
        let consumer = run(bridge, probe: probe, timeout: .milliseconds(30))
        defer { consumer.cancel(); probe.finishAll() }
        try await Phase2Fixture.waitUntil { probe.requests.count == 1 }
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
        XCTAssertEqual(failures, [0, 1])
        XCTAssertEqual(probe.cancellations, 1)
        enqueue(bridge, section: 2, generation: 1, text: "service still unavailable")
        XCTAssertEqual(failures, [0, 1, 2])
        probe.finish(0, text: "Too late")
        await consumer.value
        XCTAssertTrue(successes.isEmpty)
    }

    func testCancelledInFlightConsumerCannotFailOrCompleteReplacementWork() async throws {
        let bridge = TranslationBridge()
        let probe = TranslationProbe()
        var successes: [String] = []
        var failures: [String] = []
        bridge.onTranslated = { _, text in successes.append(text) }
        bridge.onFailed = { failures.append($0.source) }
        let first = run(bridge, probe: probe)
        enqueue(bridge, section: 0, generation: 1, text: "old meeting")
        try await Phase2Fixture.waitUntil { probe.requests.count == 1 }
        first.cancel()
        try await Phase2Fixture.waitUntil { failures == ["old meeting"] }
        bridge.restart()
        let second = run(bridge, probe: probe)
        defer { first.cancel(); second.cancel(); probe.finishAll() }
        enqueue(bridge, section: 0, generation: 1, text: "new meeting")
        try await Phase2Fixture.waitUntil { probe.requests.count == 2 }
        probe.finish(0, text: "Old result")
        await first.value
        XCTAssertFalse(bridge.isIdle)
        probe.finish(1, text: "New result")
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
        XCTAssertEqual(successes, ["New result"])
        XCTAssertEqual(failures, ["old meeting"])
    }

    func testRequestErrorAndEmptyResponseDoNotBlockOtherSpeaker() async throws {
        let bridge = TranslationBridge()
        var failures: [Int] = []
        var successes: [Int] = []
        bridge.onFailed = { failures.append($0.sectionId) }
        bridge.onTranslated = { request, _ in successes.append(request.sectionId) }
        for id in 0...2 { enqueue(bridge, section: id, generation: 1, text: "section \(id)") }
        let consumer = Task { @MainActor in
            await bridge.run(prepare: {}, translate: { request in
                if request.sectionId == 0 { throw CancellationError() }
                return request.sectionId == 1 ? "  " : "Translated"
            }, cancel: {})
        }
        defer { consumer.cancel() }
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
        XCTAssertEqual(failures, [0, 1])
        XCTAssertEqual(successes, [2])
    }

    func testContinuousSpeechGetsTranslationsWhileNewerSnapshotsArePending() async throws {
        let bridge = TranslationBridge()
        let store = CaptionStore()
        let probe = TranslationProbe()
        bridge.onTranslated = { request, text in
            store.applyTranslation(text, id: request.sectionId, generation: request.generation)
        }
        let consumer = run(bridge, probe: probe)
        defer { consumer.cancel(); probe.finishAll() }
        store.updateInterim("one", speaker: .remote)
        enqueue(bridge, section: 0, generation: try XCTUnwrap(store.beginTranslation(id: 0)), text: "one")
        try await Phase2Fixture.waitUntil { probe.requests.count == 1 }
        for index in 2...100 {
            let text = "sentence version \(index)"
            store.updateInterim(text, speaker: .remote)
            enqueue(bridge, section: 0, generation: try XCTUnwrap(store.beginTranslation(id: 0)), text: text)
        }
        store.updateInterim("my reply", speaker: .mine)
        enqueue(bridge, section: 1, generation: try XCTUnwrap(store.beginTranslation(id: 1)), text: "my reply")
        probe.finish(0, text: "First useful translation")
        try await Phase2Fixture.waitUntil { probe.requests.count == 2 }
        XCTAssertEqual(store.sections[0].targetText, "First useful translation")
        XCTAssertEqual(store.sections[0].translationState, .translating)
        XCTAssertEqual(probe.requests[1].generation, 100)
        probe.finish(1, text: "Latest translation")
        try await Phase2Fixture.waitUntil { probe.requests.count == 3 }
        probe.finish(2, text: "Reply translation")
        let idle = await bridge.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(idle)
        XCTAssertEqual(store.sections.map(\.translationState), [.done, .done])
        XCTAssertEqual(store.sections.map(\.targetText), ["Latest translation", "Reply translation"])
        XCTAssertEqual(probe.requests.count, 3)
    }

    private func enqueue(_ bridge: TranslationBridge, section: Int, generation: Int, text: String) {
        bridge.enqueue(sessionID: UUID(), generation: generation, sectionId: section,
                       source: text, target: text, hasContext: false)
    }

    private func run(_ bridge: TranslationBridge, probe: TranslationProbe,
                     timeout: Duration = .seconds(2)) -> Task<Void, Never> {
        Task { @MainActor in
            await bridge.run(requestTimeout: timeout, prepare: { probe.preparations += 1 },
                             translate: { await probe.translate($0) }, cancel: { probe.cancellations += 1 })
        }
    }
}

/// Deliberately ignores cancellation to exercise late framework replies.
@MainActor
private final class TranslationProbe {
    var preparations = 0
    var cancellations = 0
    var requests: [TranslationBridge.Request] = []
    var continuations: [Int: CheckedContinuation<String, Never>] = [:]

    func translate(_ request: TranslationBridge.Request) async -> String {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuations[index] = $0 }
    }

    func finish(_ index: Int, text: String) {
        continuations.removeValue(forKey: index)?.resume(returning: text)
    }

    func finishAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume(returning: "Stopped") }
    }
}
