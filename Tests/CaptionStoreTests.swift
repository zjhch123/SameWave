import XCTest
@testable import SameWave

@MainActor
final class CaptionStoreTests: XCTestCase {
    func testFinalCommitSwitchesFloorAndSealsPreviousSection() {
        let store = CaptionStore()

        let remote = store.appendCommitted("Hello", speaker: .remote)
        let mine = store.appendCommitted("Hi", speaker: .mine)

        XCTAssertEqual(remote.sectionId, 0)
        XCTAssertEqual(mine.sectionId, 1)
        XCTAssertEqual(mine.sealed, 0)
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine])
        XCTAssertEqual(store.sections[0].contentState, .sealed)
        XCTAssertEqual(store.sections[1].contentState, .open)
    }

    func testNonFloorInterimCannotStealFloor() {
        let store = CaptionStore()
        _ = store.updateInterim("remote speaking", speaker: .remote)

        let mine = store.updateInterim("echo", speaker: .mine)

        XCTAssertNil(mine.sectionId)
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertEqual(store.sections[0].speaker, .remote)
        XCTAssertEqual(store.sections[0].interimSource, "remote speaking")
    }

    func testSeventhSentenceStartsNewSectionWithPriorContext() {
        let store = CaptionStore()
        for index in 1...7 {
            _ = store.appendCommitted("sentence \(index)", speaker: .remote)
        }

        XCTAssertEqual(store.sections.count, 2)
        XCTAssertEqual(store.sections[0].committedSource.count, 6)
        XCTAssertEqual(store.sections[1].committedSource, ["sentence 7"])
        XCTAssertEqual(
            store.sections[1].priorContext,
            (2...6).map { "sentence \($0)" }
        )
    }

    func testRestoreKeepsIdsAndRebuildsTranslationContext() {
        let store = CaptionStore()
        store.restore(sections: [
            (id: 4, speaker: .remote, source: "earlier context", target: "上文", startedAt: .now)
        ])

        let next = store.appendCommitted("new sentence", speaker: .remote)

        XCTAssertEqual(next.sectionId, 5)
        XCTAssertEqual(store.sections.last?.priorContext, ["earlier context"])
    }

    func testStaleTranslationCannotOverwriteNewestGeneration() {
        let store = CaptionStore()
        let section = store.appendCommitted("hello", speaker: .remote).sectionId
        let old = store.beginTranslation(id: section)
        let current = store.beginTranslation(id: section)

        store.applyTranslation("旧", id: section, generation: old, final: false)
        store.applyTranslation("新", id: section, generation: current, final: false)

        XCTAssertEqual(store.section(id: section)?.targetText, "新")
    }
}
