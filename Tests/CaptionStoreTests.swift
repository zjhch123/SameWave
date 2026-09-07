import XCTest
@testable import SameWave

@MainActor
final class CaptionStoreTests: XCTestCase {
    func testFinalCommitSwitchesSpeakerAndSealsPreviousSection() {
        let store = CaptionStore()
        let remote = store.appendCommitted("Hello", speaker: .remote)
        let mine = store.appendCommitted("Hi", speaker: .mine)
        XCTAssertEqual(remote.sectionId, 0)
        XCTAssertEqual(mine.sectionId, 1)
        XCTAssertEqual(mine.sealed, 0)
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine])
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .open])
    }

    func testOverlappingInterimsAndLateFinalsKeepTheirUtteranceInBothSpeakerOrders() {
        for (first, second): (Speaker, Speaker) in [(.remote, .mine), (.mine, .remote)] {
            let store = CaptionStore()
            store.appendCommitted("Earlier sentence.", speaker: first)
            store.updateInterim("unfinished", speaker: first)
            let interruption = store.updateInterim("Let me explain", speaker: second)
            XCTAssertEqual(interruption.sectionId, 1)
            XCTAssertEqual(store.sections.map(\.contentState), [.open, .open])
            for index in 1...20 {
                XCTAssertEqual(store.updateInterim("unfinished \(index)", speaker: first).sectionId, 0)
                XCTAssertEqual(store.updateInterim("explanation \(index)", speaker: second).sectionId, 1)
            }
            XCTAssertEqual(store.sections.count, 2)
            let final = store.appendCommitted("Corrected first sentence.", speaker: first)
            XCTAssertEqual(final.sectionId, 0)
            XCTAssertEqual(final.sealed, 0)
            XCTAssertEqual(store.sections[0].sourceText, "Earlier sentence. Corrected first sentence.")
            let continued = store.updateInterim("First speaker continues", speaker: first)
            XCTAssertEqual(continued.sectionId, 2)
            XCTAssertEqual(store.sections[2].priorContext, ["Earlier sentence.", "Corrected first sentence."])
            let secondFinal = store.appendCommitted("Corrected explanation.", speaker: second)
            XCTAssertEqual(secondFinal.sectionId, 1)
            XCTAssertEqual(secondFinal.sealed, 1)
            XCTAssertEqual(store.sections.map(\.speaker), [first, second, first])
            XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .sealed, .open])
            XCTAssertEqual(store.sections.map(\.sourceText), ["Earlier sentence. Corrected first sentence.",
                "Corrected explanation.", "First speaker continues"])
        }
    }

    func testInterruptionAfterFinalSealsPreviousSectionImmediately() {
        let store = CaptionStore()
        store.appendCommitted("Remote finished.", speaker: .remote)
        let mine = store.updateInterim("My live reply", speaker: .mine)
        XCTAssertEqual(mine.sectionId, 1)
        XCTAssertEqual(mine.sealed, 0)
        XCTAssertEqual(store.sections[0].contentState, .sealed)
    }

    func testSeventhSentenceStartsNewSectionWithPriorContext() {
        for useInterim in [false, true] {
            let store = CaptionStore()
            for index in 1...7 {
                if useInterim { store.updateInterim("sentence \(index)", speaker: .remote) }
                store.appendCommitted("sentence \(index)", speaker: .remote)
            }
            XCTAssertEqual(store.sections.count, 2)
            XCTAssertEqual(store.sections[0].committedSource.count, 6)
            XCTAssertEqual(store.sections[1].committedSource, ["sentence 7"])
            XCTAssertEqual(store.sections[1].priorContext, (2...6).map { "sentence \($0)" })
        }
    }

    func testStoppingBothSpeakersPreservesCommittedAndInterimSourceExactlyOnce() {
        let store = CaptionStore()
        store.appendCommitted("Finished sentence.", speaker: .remote)
        store.updateInterim("Still speaking", speaker: .remote)
        store.updateInterim("My reply", speaker: .mine)
        store.endTurn(.remote)
        store.endTurn(.mine)
        XCTAssertEqual(store.sections.map(\.sourceText), ["Finished sentence. Still speaking", "My reply"])
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .sealed])
        XCTAssertNil(store.endTurn(.remote))
        XCTAssertEqual(store.appendCommitted("After resume", speaker: .remote).sectionId, 2)
    }

    func testEmptyInterimsDoNotCreateOrInterruptSections() {
        let store = CaptionStore()
        XCTAssertNil(store.updateInterim("  ", speaker: .remote).sectionId)
        XCTAssertTrue(store.sections.isEmpty)
        store.appendCommitted("Remote", speaker: .remote)
        XCTAssertNil(store.updateInterim("\n", speaker: .mine).sectionId)
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertEqual(store.sections[0].contentState, .open)
    }

    func testRestoreKeepsIdsAndRebuildsTranslationContext() {
        let store = CaptionStore()
        store.updateInterim("Discarded live state", speaker: .mine)
        store.restore(sections: [
            (id: 4, speaker: .remote, source: "earlier context", target: "上文", startedAt: .now)
        ])
        let next = store.appendCommitted("new sentence", speaker: .remote)
        XCTAssertEqual(next.sectionId, 5)
        XCTAssertEqual(store.sections.last?.priorContext, ["earlier context"])
        XCTAssertEqual(store.updateInterim("My next sentence", speaker: .mine).sectionId, 6)
    }

    func testRestoreDoesNotPretendMissingTranslationsAreStillRunning() {
        let store = CaptionStore()
        store.restore(sections: [
            (id: 0, speaker: .remote, source: "Saved source", target: "", startedAt: .now),
            (id: 1, speaker: .mine, source: "Translated source", target: "已翻译", startedAt: .now)
        ])
        XCTAssertEqual(store.sections.map(\.translationState), [.failed, .done])
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .sealed])
        XCTAssertEqual(store.sections[0].sourceText, "Saved source")
    }

    func testContinuousSpeechPublishesProgressBeforeLatestGenerationCompletes() throws {
        let store = CaptionStore()
        store.updateInterim("hello", speaker: .remote)
        let first = try XCTUnwrap(store.beginTranslation(id: 0))
        store.updateInterim("hello world", speaker: .remote)
        let second = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("你好", id: 0, generation: first)
        XCTAssertEqual(store.sections[0].targetText, "你好")
        XCTAssertEqual(store.sections[0].translationState, .translating)
        store.applyTranslation("你好世界", id: 0, generation: second)
        XCTAssertEqual(store.sections[0].translationState, .done)
        store.applyTranslation("旧", id: 0, generation: first)
        store.failTranslation(id: 0, generation: first)
        XCTAssertEqual(store.sections[0].targetText, "你好世界")
        XCTAssertEqual(store.sections[0].translationState, .done)
        store.updateInterim("hello world again", speaker: .remote)
        XCTAssertNotNil(store.beginTranslation(id: 0))
        XCTAssertEqual(store.sections[0].translationState, .translating)
    }

    func testDuplicateInterimFinalAndSealDoNotInvalidateInFlightTranslation() throws {
        let store = CaptionStore()
        store.updateInterim("hello", speaker: .remote)
        let generation = try XCTUnwrap(store.beginTranslation(id: 0))
        store.updateInterim("hello", speaker: .remote)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.appendCommitted("hello", speaker: .remote)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.endTurn(.remote)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.applyTranslation("你好", id: 0, generation: generation)
        XCTAssertEqual(store.sections[0].translationState, .done)
    }

    func testEmptyTranslationFailsAndSameSourceCanRetry() throws {
        let store = CaptionStore()
        store.appendCommitted("hello", speaker: .remote)
        let first = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("  ", id: 0, generation: first)
        XCTAssertEqual(store.sections[0].translationState, .failed)
        let retry = try XCTUnwrap(store.beginTranslation(id: 0))
        XCTAssertGreaterThan(retry, first)
        store.applyTranslation("你好", id: 0, generation: retry)
        XCTAssertEqual(store.sections[0].translationState, .done)
        XCTAssertEqual(store.sections[0].sourceText, "hello")
    }
}
