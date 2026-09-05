import Foundation
import XCTest
@testable import SameWave

@MainActor
final class TranslationBridgeTests: XCTestCase {
    func testCoalescesPerSectionAndPreservesCrossSectionOrder() async {
        let bridge = TranslationBridge()
        let sessionID = UUID()
        bridge.enqueue(sessionID: sessionID, generation: 1, sectionId: 1,
                       source: "old", target: "old", isFinal: false, hasContext: false)
        bridge.enqueue(sessionID: sessionID, generation: 1, sectionId: 2,
                       source: "two", target: "two", isFinal: false, hasContext: false)
        bridge.enqueue(sessionID: sessionID, generation: 2, sectionId: 1,
                       source: "new", target: "new", isFinal: true, hasContext: false)

        let first = await bridge.next()
        let second = await bridge.next()

        XCTAssertEqual(first?.sectionId, 1)
        XCTAssertEqual(first?.source, "new")
        XCTAssertEqual(first?.generation, 2)
        XCTAssertEqual(second?.sectionId, 2)
        if let first { bridge.complete(first) }
        if let second { bridge.complete(second) }
        XCTAssertTrue(bridge.isIdle)
    }

    func testWaitUntilIdleCompletesWhenRequestFinishes() async {
        let bridge = TranslationBridge()
        bridge.enqueue(sessionID: UUID(), generation: 1, sectionId: 1,
                       source: "one", target: "one", isFinal: true, hasContext: false)
        let request = await bridge.next()
        let waiter = Task { @MainActor in
            await bridge.waitUntilIdle(timeout: .seconds(1))
        }

        if let request { bridge.complete(request) }

        let completed = await waiter.value
        XCTAssertTrue(completed)
    }
}
